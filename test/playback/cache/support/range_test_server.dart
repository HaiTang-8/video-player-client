import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

/// 本机 Range 测试源站：可注入首字节延迟、限速与 302 跳转，用于单测和起播基准
///
/// - `/media/<name>`：支持 GET / HEAD 与单段 Range
/// - `/redirect/<name>`：302 到带签名参数的 `/media/<name>`，模拟网盘直链
class RangeTestServer {
  RangeTestServer._(this._server, this.file, this.contentType);

  static const _chunkSize = 64 * 1024;

  static Future<RangeTestServer> start(
    File file, {
    Duration firstByteLatency = Duration.zero,
    int? bytesPerSecond,
    String contentType = 'video/x-matroska',
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final instance =
        RangeTestServer._(server, file, contentType)
          ..firstByteLatency = firstByteLatency
          ..bytesPerSecond = bytesPerSecond;
    server.listen((request) => unawaited(instance._handle(request)));
    return instance;
  }

  final HttpServer _server;
  final File file;
  final String contentType;

  /// 每个请求（含 HEAD 与 302）返回响应头之前的等待时间
  Duration firstByteLatency = Duration.zero;

  /// 按请求起点单独设置首字节延迟（返回 null 时用 [firstByteLatency]）
  Duration? Function(int start)? firstByteLatencyFor;

  /// 单个连接的限速；null 表示不限速
  int? bytesPerSecond;

  /// 按请求起点单独限速（返回 null 时用 [bytesPerSecond]），模拟个别连接特别慢
  int? Function(int start)? bytesPerSecondFor;

  /// 请求必须带上的请求头，缺少或不一致时返回 [rejectStatus]
  Map<String, String> requiredHeaders = const {};

  /// 请求头不符合时的状态码；网盘 CDN 在凭据失效时返回 412
  int rejectStatus = HttpStatus.unauthorized;

  /// 正在处理的请求数，以及出现过的最大并发数
  int active = 0;
  int peakActive = 0;

  int requestCount = 0;
  int bytesServed = 0;
  final List<String> requestLog = [];

  /// 每个请求的开始（`>`）和结束（`<`，含已发送字节数），时间相对上次 [resetStats]
  final List<String> timeline = [];
  final Stopwatch _clock = Stopwatch()..start();
  int _signature = 0;

  String get _name => Uri.encodeComponent(file.uri.pathSegments.last);

  Uri get mediaUri =>
      Uri.parse('http://127.0.0.1:${_server.port}/media/$_name');

  Uri get redirectUri =>
      Uri.parse('http://127.0.0.1:${_server.port}/redirect/$_name');

  void resetStats() {
    requestCount = 0;
    bytesServed = 0;
    requestLog.clear();
    timeline.clear();
    _clock.reset();
  }

  void _mark(String event) =>
      timeline.add('+${_clock.elapsedMilliseconds}ms $event');

  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    requestCount++;
    peakActive = math.max(peakActive, ++active);
    try {
      await _handleRequest(request);
    } finally {
      active--;
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final range = request.headers.value(HttpHeaders.rangeHeader);
    final line = '${request.method} ${request.uri.path} ${range ?? '-'}';
    requestLog.add(line);
    _mark('> $line');
    final response = request.response;
    try {
      final rangeStart =
          int.tryParse(RegExp(r'bytes=(\d+)-').firstMatch(range ?? '')?.group(1) ?? '') ?? 0;
      final latency = firstByteLatencyFor?.call(rangeStart) ?? firstByteLatency;
      if (latency > Duration.zero) {
        await Future<void>.delayed(latency);
      }
      final segments = request.uri.pathSegments;
      final authorized = requiredHeaders.entries.every(
        (e) => request.headers.value(e.key) == e.value,
      );
      if (!authorized) {
        response.statusCode = rejectStatus;
      } else if (segments.length != 2) {
        response.statusCode = HttpStatus.notFound;
      } else if (segments.first == 'redirect') {
        response
          ..statusCode = HttpStatus.found
          ..headers.set(
            HttpHeaders.locationHeader,
            '/media/$_name?sig=${++_signature}',
          );
      } else if (segments.first == 'media') {
        await _serveMedia(request, range, line);
        return;
      } else {
        response.statusCode = HttpStatus.notFound;
      }
      await response.close();
    } on HttpException {
      // 客户端提前断开属于正常情况（播放器 seek、关闭）
    } on SocketException {
      // 同上
    } catch (e) {
      try {
        response.statusCode = HttpStatus.internalServerError;
        response.write('$e');
      } catch (_) {}
      await response.close().catchError((_) {});
    }
  }

  Future<void> _serveMedia(
    HttpRequest request,
    String? rangeHeader,
    String line,
  ) async {
    final response = request.response;
    final size = await file.length();
    final stat = await file.stat();
    response.headers
      ..set(HttpHeaders.acceptRangesHeader, 'bytes')
      ..set(HttpHeaders.contentTypeHeader, contentType)
      ..set(
        HttpHeaders.etagHeader,
        '"$size-${stat.modified.millisecondsSinceEpoch}"',
      )
      ..set(HttpHeaders.lastModifiedHeader, HttpDate.format(stat.modified));

    var start = 0;
    var end = size - 1;
    if (rangeHeader != null) {
      final parsed = parseRange(rangeHeader, size);
      if (parsed == null) {
        response
          ..statusCode = HttpStatus.requestedRangeNotSatisfiable
          ..headers.set(HttpHeaders.contentRangeHeader, 'bytes */$size');
        await response.close();
        return;
      }
      (start, end) = parsed;
      response
        ..statusCode = HttpStatus.partialContent
        ..headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes $start-$end/$size',
        );
    }
    response.contentLength = end - start + 1;
    if (request.method == 'HEAD') {
      await response.close();
      return;
    }

    // 接管 socket：对端断开后 HttpResponse.flush 会一直挂起，只有读端的 EOF 能及时发现
    response.persistentConnection = false;
    final socket = await response.detachSocket();
    final gone = Completer<void>();
    socket.listen(
      (_) {},
      onDone: () => gone.isCompleted ? null : gone.complete(),
      onError: (_) => gone.isCompleted ? null : gone.complete(),
      cancelOnError: true,
    );
    final raf = await file.open();
    final watch = Stopwatch()..start();
    var sent = 0;
    try {
      await raf.setPosition(start);
      var remaining = end - start + 1;
      while (remaining > 0 && !gone.isCompleted) {
        final chunk = await raf.read(math.min(_chunkSize, remaining));
        if (chunk.isEmpty) break;
        socket.add(chunk);
        await Future.any([socket.flush(), gone.future]);
        if (gone.isCompleted) break;
        remaining -= chunk.length;
        sent += chunk.length;
        bytesServed += chunk.length;
        final limit = bytesPerSecondFor?.call(start) ?? bytesPerSecond;
        if (limit != null) {
          final due = Duration(microseconds: sent * 1000000 ~/ limit);
          final wait = due - watch.elapsed;
          if (wait > Duration.zero) {
            await Future.any([Future<void>.delayed(wait), gone.future]);
          }
        }
      }
      if (!gone.isCompleted) await socket.flush();
    } finally {
      _mark('< $line sent=${sent ~/ 1024}KiB');
      socket.destroy();
      await raf.close();
    }
  }

  /// 解析单段 Range，返回闭区间；不合法或越界时返回 null
  static (int, int)? parseRange(String header, int size) {
    final match = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(header.trim());
    if (match == null || size <= 0) return null;
    final first = match.group(1)!;
    final last = match.group(2)!;
    if (first.isEmpty) {
      final suffix = int.tryParse(last);
      if (suffix == null || suffix <= 0) return null;
      return (math.max(0, size - suffix), size - 1);
    }
    final start = int.parse(first);
    if (start >= size) return null;
    final end = last.isEmpty ? size - 1 : math.min(int.parse(last), size - 1);
    return end < start ? null : (start, end);
  }
}
