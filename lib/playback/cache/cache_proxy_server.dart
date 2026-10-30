import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'byte_range.dart';
import 'cache_eviction.dart';
import 'cache_store.dart';

/// 代理隔离区的入口参数
final class CacheProxyBoot {
  const CacheProxyBoot(
    this.reply,
    this.token, {
    this.events,
    this.cacheRoot,
    this.blockSize = 4 << 20,
  });

  final SendPort reply;
  final String token;

  /// 代理请求主隔离区的通道（例如刷新上游地址）
  final SendPort? events;

  /// 为空时只透传、不缓存
  final String? cacheRoot;
  final int blockSize;
}

/// 代理隔离区：只监听本机回环地址。登记为可缓存的条目，已缓存的部分直接读盘，
/// 缺失的部分按缺口向上游请求、边转发边写入；其余条目透传
///
/// 转发都经过 addStream：播放器读得慢时上游读取也随之变慢；播放器断开后，
/// 下一次写入失败时会取消上游订阅并关闭上游连接
Future<void> cacheProxyMain(CacheProxyBoot boot) async {
  final root = boot.cacheRoot;
  CacheStore? store;
  if (root != null) {
    store = CacheStore(Directory(root), blockSize: boot.blockSize);
    await store.open();
  }
  final server = _CacheProxyServer(boot.token, store, boot.events);
  final commands = ReceivePort();
  final port = await server.bind();
  boot.reply.send(<String, Object>{
    'port': port,
    'commands': commands.sendPort,
  });
  await for (final message in commands) {
    final map = message as Map<String, Object?>;
    final reply = map['reply'] as SendPort?;
    final result = await server.command(map);
    reply?.send(result);
  }
}

class _Entry {
  _Entry(
    this.id,
    this.url,
    this.headers, {
    this.cacheId,
    this.refreshable = false,
    this.filePath,
    this.storageId,
    this.serverId,
    this.itemKey,
    this.connections = 1,
  }) {
    if (url != null) _upstream.complete(true);
  }

  /// 并发回源连接数；大于 1 时按块并发（网盘单连接限速），同一条目的所有请求共用
  int connections;
  late final _Slots slots = _Slots(() => connections);

  /// 每次换上游地址加一：请求失败时据此判断别的请求是否已经刷新过
  int generation = 0;
  Future<bool>? refreshing;

  /// 透传模式下探测到的文件信息（并发回源需要先知道大小）
  _UpstreamInfo? probed;
  Future<_UpstreamInfo?>? probing;

  final String id;
  final String? filePath;
  final int? storageId;
  final String? serverId;
  final String? itemKey;

  /// 命中缓存时先登记、后台解析完成后再补上；为空时回源要等 [upstreamReady]
  Uri? url;
  Map<String, String> headers;
  final Completer<bool> _upstream = Completer<bool>();

  /// 上游地址可用时为 true，后台解析失败时为 false
  Future<bool> get upstreamReady => _upstream.future;

  void setUpstream(Uri value, Map<String, String> newHeaders) {
    url = value;
    headers = newHeaders;
    generation++;
    if (!_upstream.isCompleted) _upstream.complete(true);
  }

  void failUpstream() {
    if (!_upstream.isCompleted) _upstream.complete(false);
  }

  final String? cacheId;
  final bool refreshable;

  /// 打开阶段截止时间：期间文件首尾的读取记为固定区间
  DateTime? openingUntil;

  /// 等待与下一次读取偏移配对的播放位置（打开时的起播位置或 seek 目标）
  int? pendingSampleMs;
}

/// 上游响应的关键信息
final class _UpstreamInfo {
  _UpstreamInfo(HttpClientResponse response)
    : status = response.statusCode,
      contentType = response.headers.value(HttpHeaders.contentTypeHeader),
      etag = response.headers.value(HttpHeaders.etagHeader),
      lastModified = response.headers.value(HttpHeaders.lastModifiedHeader),
      contentLength = response.contentLength {
    final match = RegExp(
      r'bytes (\d+)-(\d+)/(\d+)',
    ).firstMatch(response.headers.value(HttpHeaders.contentRangeHeader) ?? '');
    if (status == HttpStatus.partialContent && match != null) {
      start = int.parse(match.group(1)!);
      size = int.parse(match.group(3)!);
    } else if (status == HttpStatus.ok && contentLength >= 0) {
      start = 0;
      size = contentLength;
    }
  }

  final int status;
  final String? contentType;
  final String? etag;
  final String? lastModified;
  final int contentLength;
  int? start;
  int? size;

  bool get usable => start != null && size != null && size! > 0;
}

class _CacheProxyServer {
  _CacheProxyServer(this._token, this._store, this._events);

  static const _forwardedHeaders = [
    HttpHeaders.contentTypeHeader,
    HttpHeaders.contentRangeHeader,
    HttpHeaders.acceptRangesHeader,
    HttpHeaders.etagHeader,
    HttpHeaders.lastModifiedHeader,
  ];

  /// 打开阶段只把文件首尾这些范围内的读取记为固定区间（封装头、索引），避免固定住续播点本身
  static const _pinZone = 64 << 20;
  static const _openingTimeout = Duration(seconds: 15);
  static const _upstreamTimeout = Duration(seconds: 30);
  static const _enforceInterval = Duration(seconds: 1);

  /// 拖动耗时日志记录交付前 4 MiB 的时间（大致是播放器恢复播放所需的数据量）
  static const _leadBytes = 4 << 20;

  /// 切出的每一半至少这么大：新请求的首字节延迟（实测约 0.45 秒）要抵得过省下的时间。
  /// 实测 256 KiB 时切分次数翻倍、拖动反而变慢
  static const _minSplit = 512 << 10;

  final String _token;
  final CacheStore? _store;
  final SendPort? _events;
  final Map<String, _Entry> _entries = {};
  final HttpClient _client =
      HttpClient()
        ..autoUncompress = false
        ..connectionTimeout = const Duration(seconds: 15)
        ..idleTimeout = const Duration(seconds: 15)
        // 环境变量里的 HTTP 代理不会排除本机地址
        ..findProxy =
            (uri) =>
                InternetAddress.tryParse(uri.host)?.isLoopback ??
                        uri.host == 'localhost'
                    ? 'DIRECT'
                    : HttpClient.findProxyFromEnvironment(uri);
  HttpServer? _server;
  int _port = 0;
  int _quota = 0;

  /// 实际上限：写入只是把剩余空间换成已用空间，两者之和不变，所以收到新配额或剩余空间时算一次即可
  int _limit = 0;
  DateTime _lastEnforce = DateTime.fromMillisecondsSinceEpoch(0);
  final Map<String, int> _stats = {
    'requests': 0,
    'bytes': 0,
    'cacheBytes': 0,
    'upstreamBytes': 0,
    'active': 0,
    'cancelledUpstreams': 0,
    'rebinds': 0,
    'refreshes': 0,
    'blocks': 0,
    'peakBlocks': 0,
    'splits': 0,
  };
  int _activeBlocks = 0;

  /// 并发回源的请求序号：越新的请求越优先拿到连接（拖动进度、读取文件尾的索引）
  int _streamSeq = 0;

  Future<int> bind() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, _port);
    server
      ..autoCompress = false
      ..idleTimeout = const Duration(seconds: 30);
    server.listen((request) => unawaited(_handle(request)));
    _server = server;
    _port = server.port;
    return _port;
  }

  Future<Object?> command(Map<String, Object?> message) async {
    final id = message['id'] as String?;
    final entry = id == null ? null : _entries[id];
    final cacheId = entry?.cacheId;
    switch (message['cmd']) {
      case 'register':
        final url = message['url'] as String?;
        final registered = _Entry(
          id!,
          url == null ? null : Uri.parse(url),
          Map<String, String>.from(message['headers'] as Map),
          cacheId: _store == null ? null : message['cacheId'] as String?,
          refreshable: message['refreshable'] == true,
          filePath: message['filePath'] as String?,
          storageId: message['storageId'] as int?,
          serverId: message['serverId'] as String?,
          itemKey: message['itemKey'] as String?,
          connections: math.max(1, message['connections'] as int? ?? 1),
        );
        _entries[id] = registered;
        final registeredCacheId = registered.cacheId;
        if (registeredCacheId != null) {
          _store!.describe(
            registeredCacheId,
            filePath: registered.filePath,
            storageId: registered.storageId,
            serverId: registered.serverId,
            itemKey: registered.itemKey,
          );
        }
        return true;
      case 'upstream':
        final connections = message['connections'] as int?;
        if (entry != null && connections != null) {
          entry.connections = math.max(1, connections);
        }
        entry?.setUpstream(
          Uri.parse(message['url'] as String),
          Map<String, String>.from(message['headers'] as Map),
        );
        return true;
      case 'upstreamFailed':
        entry?.failUpstream();
        return true;
      case 'lookup':
        final found = _store?.findByItem(
          message['serverId'] as String,
          message['itemKey'] as String,
        );
        return found == null
            ? null
            : <String, Object?>{
              'cacheId': found.id,
              'filePath': found.filePath,
              'storageId': found.storageId,
              'size': found.size,
              'cachedBytes': found.cachedBytes,
            };
      case 'unregister':
        _entries.remove(id);
        return true;
      case 'opening':
        entry
          ?..openingUntil = DateTime.now().add(_openingTimeout)
          ..pendingSampleMs = message['positionMs'] as int?;
        return true;
      case 'opened':
        entry?.openingUntil = null;
        return true;
      case 'seek':
        entry?.pendingSampleMs = message['positionMs'] as int?;
        return true;
      case 'progress':
        if (cacheId != null) {
          _store!
            ..reportPlayback(
              cacheId,
              positionMs: message['positionMs'] as int,
              durationMs: message['durationMs'] as int?,
            )
            ..touch(cacheId);
        }
        return true;
      case 'limits':
        _quota = message['quotaBytes'] as int;
        final free = message['freeBytes'] as int?;
        // 剩余空间未知（桌面端没有查询接口）时只按配额
        _limit =
            free == null || free <= 0
                ? _quota
                : effectiveCacheLimit(
                  quotaBytes: _quota,
                  usedBytes: _store?.usedBytes ?? 0,
                  freeBytes: free,
                );
        await _store?.enforce(_limit, force: true);
        return true;
      case 'usage':
        return <String, int>{
          'bytes': _store?.usedBytes ?? 0,
          'entries': _store?.entries.length ?? 0,
          'limit': _limit,
        };
      case 'entries':
        final metas =
            (_store?.entries.toList() ?? [])
              ..sort((a, b) => b.lastAccess.compareTo(a.lastAccess));
        return [
          for (final meta in metas)
            <String, Object?>{
              'id': meta.id,
              'filePath': meta.filePath,
              'cachedBytes': meta.cachedBytes,
              'size': meta.size,
              'lastAccess': meta.lastAccess.millisecondsSinceEpoch,
            },
        ];
      case 'remove':
        await _store?.remove(message['cacheId'] as String);
        return true;
      case 'clear':
        await _store?.clear();
        return true;
      case 'flush':
        await _store?.flush();
        return true;
      case 'ensure':
        return _ensureListening();
      case 'closeListener':
        await _server?.close(force: true);
        _server = null;
        return true;
      case 'stats':
        return Map<String, int>.from(_stats);
    }
    return null;
  }

  /// iOS 挂起后监听 socket 可能被系统回收；在同一端口重新绑定，保证已发出的代理地址仍然可用
  Future<bool> _ensureListening() async {
    if (_server != null && await _selfCheck()) return true;
    await _server?.close(force: true);
    _server = null;
    for (var attempt = 0; attempt < 5; attempt++) {
      try {
        await bind();
        _count('rebinds');
        return true;
      } on SocketException {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
    return false;
  }

  Future<bool> _selfCheck() async {
    try {
      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        _port,
        timeout: const Duration(milliseconds: 300),
      );
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  void _count(String name, [int by = 1]) =>
      _stats[name] = (_stats[name] ?? 0) + by;

  Future<void> _handle(HttpRequest request) async {
    _count('requests');
    final response = request.response;
    final segments = request.uri.pathSegments;
    final entry =
        segments.length == 3 && segments[0] == _token && segments[1] == 'e'
            ? _entries[segments[2]]
            : null;
    if (entry == null) {
      response.statusCode = HttpStatus.notFound;
      await response.close().catchError((_) {});
      return;
    }
    if (request.method != 'GET' && request.method != 'HEAD') {
      response
        ..statusCode = HttpStatus.methodNotAllowed
        ..headers.set(HttpHeaders.allowHeader, 'GET, HEAD');
      await response.close().catchError((_) {});
      return;
    }

    _count('active');
    final cacheId = entry.cacheId;
    final store = _store;
    try {
      if (cacheId != null && store != null && _quota > 0) {
        store.acquire(cacheId);
        try {
          await _serveCached(request, entry, cacheId, store);
        } finally {
          store.release(cacheId);
        }
      } else if (entry.connections > 1) {
        await _serveParallel(request, entry);
      } else {
        await _passThrough(request, entry);
      }
    } catch (_) {
      await response.close().catchError((_) {});
    } finally {
      _count('active', -1);
    }
  }

  Future<void> _passThrough(HttpRequest request, _Entry entry) async {
    final response = request.response;
    final upstream = await _openUpstream(
      request.method,
      entry,
      request.headers.value(HttpHeaders.rangeHeader),
    );
    if (upstream == null) {
      response.statusCode = HttpStatus.badGateway;
      await response.close();
      return;
    }
    _copyUpstreamHeaders(upstream, response);
    if (request.method == 'HEAD') {
      await upstream.drain<void>();
      await response.close();
      return;
    }
    var forwarded = 0;
    await response.addStream(
      upstream.map((chunk) {
        forwarded += chunk.length;
        _count('bytes', chunk.length);
        return chunk;
      }),
    );
    if (upstream.contentLength >= 0 && forwarded < upstream.contentLength) {
      _count('cancelledUpstreams');
    }
    await response.close();
  }

  Future<void> _serveCached(
    HttpRequest request,
    _Entry entry,
    String id,
    CacheStore store,
  ) async {
    final response = request.response;
    final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
    final meta = store[id];
    if (meta == null) {
      if (entry.connections > 1) {
        // 并发回源要先知道文件大小：探测后按已知大小的流程处理
        final info = await _probeOnce(entry);
        if (info == null) {
          response.statusCode = HttpStatus.badGateway;
          await response.close();
          return;
        }
        await _prepare(store, id, entry, info);
        await _serveCached(request, entry, id, store);
        return;
      }
      await _firstContact(request, entry, id, store, rangeHeader);
      return;
    }

    final size = meta.size;
    var start = 0;
    var end = size;
    if (rangeHeader != null) {
      final parsed = _parseRange(rangeHeader, size);
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
          'bytes $start-${end - 1}/$size',
        );
    }
    response.headers
      ..set(HttpHeaders.acceptRangesHeader, 'bytes')
      ..set(
        HttpHeaders.contentTypeHeader,
        meta.contentType ?? 'application/octet-stream',
      );
    if (meta.etag != null) {
      response.headers.set(HttpHeaders.etagHeader, meta.etag!);
    }
    if (meta.lastModified != null) {
      response.headers.set(HttpHeaders.lastModifiedHeader, meta.lastModified!);
    }
    response.contentLength = end - start;
    if (request.method == 'HEAD') {
      await response.close();
      return;
    }

    _recordStart(entry, id, store, start);
    if (entry.connections > 1) {
      final delivered = await _sendDetached(
        response,
        _parallelBody(
          entry,
          start,
          end,
          meta.size,
          meta.etag,
          store: store,
          id: id,
        ),
      );
      if (delivered < end - start) _count('cancelledUpstreams');
      _recordRead(entry, id, store, ByteRange(start, start + delivered));
      return;
    }
    var delivered = 0;
    try {
      await response.addStream(
        _assemble(entry, id, store, start, end).map((chunk) {
          delivered += chunk.length;
          _count('bytes', chunk.length);
          return chunk;
        }),
      );
    } finally {
      if (delivered < end - start) _count('cancelledUpstreams');
      _recordRead(entry, id, store, ByteRange(start, start + delivered));
    }
    await response.close();
  }

  /// 还不知道文件大小：按播放器的原始 Range 请求上游，拿到大小后建立条目并边转发边写入
  Future<void> _firstContact(
    HttpRequest request,
    _Entry entry,
    String id,
    CacheStore store,
    String? rangeHeader,
  ) async {
    final response = request.response;
    final upstream = await _openUpstream(request.method, entry, rangeHeader);
    if (upstream == null) {
      response.statusCode = HttpStatus.badGateway;
      await response.close();
      return;
    }
    final info = _UpstreamInfo(upstream);
    _copyUpstreamHeaders(upstream, response);
    if (info.usable) {
      await store.prepare(
        id,
        size: info.size!,
        contentType: info.contentType,
        etag: info.etag,
        lastModified: info.lastModified,
        filePath: entry.filePath,
        storageId: entry.storageId,
        serverId: entry.serverId,
        itemKey: entry.itemKey,
      );
    }
    if (request.method == 'HEAD' || !info.usable) {
      if (request.method == 'HEAD') {
        await upstream.drain<void>();
      } else {
        await response.addStream(upstream);
      }
      await response.close();
      return;
    }

    final start = info.start!;
    _recordStart(entry, id, store, start);
    final writer = _writable ? store.writer(id, start) : null;
    var delivered = 0;
    try {
      await response.addStream(
        upstream.asyncMap((chunk) async {
          await writer?.add(chunk);
          delivered += chunk.length;
          _count('bytes', chunk.length);
          _count('upstreamBytes', chunk.length);
          return chunk;
        }),
      );
    } finally {
      await writer?.close();
      if (info.contentLength >= 0 && delivered < info.contentLength) {
        _count('cancelledUpstreams');
      }
      _recordRead(entry, id, store, ByteRange(start, start + delivered));
      _maybeEnforce(store);
    }
    await response.close();
  }

  /// 按顺序拼出 [start, end)：已缓存的部分读盘，缺口向上游请求并写入
  Stream<List<int>> _assemble(
    _Entry entry,
    String id,
    CacheStore store,
    int start,
    int end,
  ) async* {
    var cursor = start;
    while (cursor < end) {
      final meta = store[id];
      if (meta == null) throw StateError('cache entry $id was invalidated');
      final run = math.min(meta.cachedRunFrom(cursor), end - cursor);
      if (run > 0) {
        await for (final chunk in store.openRead(
          id,
          ByteRange(cursor, cursor + run),
        )) {
          _count('cacheBytes', chunk.length);
          yield chunk;
        }
        cursor += run;
        continue;
      }
      final gap = meta.missing(ByteRange(cursor, end)).first;
      yield* _fetchGap(entry, id, store, gap);
      cursor = gap.end;
    }
  }

  Stream<List<int>> _fetchGap(
    _Entry entry,
    String id,
    CacheStore store,
    ByteRange gap,
  ) async* {
    final meta = store[id]!;
    final upstream = await _openUpstream(
      'GET',
      entry,
      'bytes=${gap.start}-${gap.end - 1}',
    );
    if (upstream == null) throw const HttpException('upstream unavailable');
    final info = _UpstreamInfo(upstream);
    final changed =
        info.size != null && info.size != meta.size ||
        info.etag != null && meta.etag != null && info.etag != meta.etag;
    if (changed) {
      await upstream.drain<void>().catchError((_) {});
      // 上游文件已变化：作废旧缓存，本次请求失败，播放器重试时按新条目处理
      await store.prepare(
        id,
        size: info.size ?? meta.size,
        contentType: info.contentType,
        etag: info.etag,
        lastModified: info.lastModified,
        filePath: entry.filePath,
        storageId: entry.storageId,
        serverId: entry.serverId,
        itemKey: entry.itemKey,
      );
      throw const HttpException('upstream file changed');
    }
    if (info.status != HttpStatus.partialContent || info.start != gap.start) {
      await upstream.drain<void>().catchError((_) {});
      throw HttpException('unexpected upstream status ${info.status}');
    }

    final writer = _writable ? store.writer(id, gap.start) : null;
    var received = 0;
    try {
      await for (final chunk in upstream) {
        final take = math.min(chunk.length, gap.length - received);
        final piece = take == chunk.length ? chunk : chunk.sublist(0, take);
        await writer?.add(piece);
        received += take;
        _count('upstreamBytes', take);
        yield piece;
        if (received >= gap.length) break;
      }
    } finally {
      await writer?.close();
      _maybeEnforce(store);
    }
    if (received < gap.length) {
      throw const HttpException('upstream ended early');
    }
  }

  /// 透传 + 并发回源：先探测文件大小，按播放器的 Range 自行组织响应头
  Future<void> _serveParallel(HttpRequest request, _Entry entry) async {
    final response = request.response;
    final info = entry.probed ??= await _probeOnce(entry);
    if (info == null) {
      response.statusCode = HttpStatus.badGateway;
      await response.close();
      return;
    }
    final size = info.size!;
    var start = 0;
    var end = size;
    final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
    if (rangeHeader != null) {
      final parsed = _parseRange(rangeHeader, size);
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
          'bytes $start-${end - 1}/$size',
        );
    }
    response.headers
      ..set(HttpHeaders.acceptRangesHeader, 'bytes')
      ..set(
        HttpHeaders.contentTypeHeader,
        info.contentType ?? 'application/octet-stream',
      );
    if (info.etag != null) {
      response.headers.set(HttpHeaders.etagHeader, info.etag!);
    }
    if (info.lastModified != null) {
      response.headers.set(HttpHeaders.lastModifiedHeader, info.lastModified!);
    }
    response.contentLength = end - start;
    if (request.method == 'HEAD') {
      await response.close();
      return;
    }
    final delivered = await _sendDetached(
      response,
      _parallelBody(entry, start, end, size, info.etag),
    );
    if (delivered < end - start) _count('cancelledUpstreams');
  }

  /// 接管 socket 发送响应体：HttpResponse 只有在下一次写入失败时才发现播放器断开，
  /// 并发回源时等待块的间隙可能很长，所以改为监听读端的 EOF，断开后立即取消响应体（中止在途块）。
  /// 返回已发送的字节数；响应体出错时提前断开连接，交给播放器重试
  Future<int> _sendDetached(
    HttpResponse response,
    Stream<List<int>> body,
  ) async {
    response.persistentConnection = false;
    final socket = await response.detachSocket();
    final gone = Completer<void>();
    void markGone([Object? _]) {
      if (!gone.isCompleted) gone.complete();
    }

    socket.listen(
      (_) {},
      onDone: markGone,
      onError: markGone,
      cancelOnError: true,
    );
    var sent = 0;
    final finished = Completer<void>();
    late final StreamSubscription<List<int>> subscription;
    subscription = body.listen(
      (chunk) {
        socket.add(chunk);
        sent += chunk.length;
        _count('bytes', chunk.length);
        subscription.pause();
        Future.any([socket.flush(), gone.future]).then(
          (_) => gone.isCompleted ? null : subscription.resume(),
          onError: markGone,
        );
      },
      onError: (Object _) => finished.isCompleted ? null : finished.complete(),
      onDone: () => finished.isCompleted ? null : finished.complete(),
      cancelOnError: true,
    );
    await Future.any([finished.future, gone.future]);
    await subscription.cancel();
    if (!gone.isCompleted && sent > 0) {
      await socket.flush().catchError((Object _) {});
    }
    socket.destroy();
    return sent;
  }

  /// 并发条目的响应体：缓存模式下已缓存的部分读盘、缺口并发回源并写入；透传模式全部并发回源。
  /// 最多预读 connections 个块，下游暂停时不再发起新块；取消时立即中止在途块。
  /// 上游文件变化时作废旧缓存（透传模式下清掉探测结果，下次请求重新探测）
  Stream<List<int>> _parallelBody(
    _Entry entry,
    int start,
    int end,
    int size,
    String? etag, {
    CacheStore? store,
    String? id,
  }) {
    final priority = ++_streamSeq;
    final pending = <_Block>[];
    final controller = StreamController<List<int>>();
    var cancelled = false;
    Completer<void>? resumed;
    final clock = Stopwatch()..start();
    var delivered = 0;
    int? firstMs;
    int? leadMs;
    var splits = 0;

    Future<void> emit(List<int> chunk) async {
      firstMs ??= clock.elapsedMilliseconds;
      delivered += chunk.length;
      if (leadMs == null && delivered >= _leadBytes) {
        leadMs = clock.elapsedMilliseconds;
      }
      controller.add(chunk);
      while (controller.isPaused && !cancelled) {
        await (resumed ??= Completer<void>()).future;
      }
    }

    Future<void> fetchRange(int from, int to) async {
      final writer =
          store != null && _writable ? store.writer(id!, from) : null;
      var next = from;
      var index = 0;
      late final void Function() splitIdle;

      void launch(_Block block) {
        block.result = _fetchBlock(entry, block, size, etag)..ignore();
        block.result.then<void>(
          (_) => splitIdle(),
          onError: (Object _) {},
        );
      }

      void fill() {
        while (!cancelled && pending.length < entry.connections && next < to) {
          final end = math.min(
            next + _blockSizeAt(index),
            to,
          );
          final block = _Block(next, end, priority, index++);
          launch(block);
          pending.add(block);
          next = end;
        }
      }

      // 动态分段：有连接空闲时，把排在最前面、剩余最多的在途块对半切开，后一半交给空闲连接，
      // 避免最慢的块拖住后面已经到达的数据
      splitIdle = () {
        if (cancelled || entry.connections <= 1) return;
        while (pending.where((b) => !b.done).length < entry.connections) {
          final at = pending.indexWhere(
            (b) => !b.done && b.remaining >= 2 * _minSplit,
          );
          if (at < 0) return;
          final victim = pending[at];
          final tail = victim.end;
          final mid = victim.splitPoint;
          if (!victim.shrinkTo(mid)) return;
          final piece = _Block(mid, tail, priority, victim.index);
          launch(piece);
          pending.insert(at + 1, piece);
          splits++;
          _count('splits');
        }
      };

      try {
        fill();
        while (pending.isNotEmpty && !cancelled) {
          final bytes = await pending.first.result;
          if (cancelled) return;
          pending.removeAt(0);
          fill();
          splitIdle();
          await writer?.add(bytes);
          _count('upstreamBytes', bytes.length);
          await emit(bytes);
        }
      } finally {
        await writer?.close();
        if (store != null) _maybeEnforce(store);
      }
    }

    Future<void> pump() async {
      try {
        var cursor = start;
        while (cursor < end && !cancelled) {
          var to = end;
          if (store != null) {
            final meta = store[id!];
            if (meta == null) {
              throw StateError('cache entry $id was invalidated');
            }
            final run = math.min(meta.cachedRunFrom(cursor), end - cursor);
            if (run > 0) {
              await for (final chunk in store.openRead(
                id,
                ByteRange(cursor, cursor + run),
              )) {
                if (cancelled) return;
                _count('cacheBytes', chunk.length);
                await emit(chunk);
              }
              cursor += run;
              continue;
            }
            to = meta.missing(ByteRange(cursor, end)).first.end;
          }
          await fetchRange(cursor, to);
          cursor = to;
        }
        if (!cancelled) await controller.close();
      } on _Cancelled {
        // 播放器断开，在途块已中止
      } catch (e, st) {
        if (e is _UpstreamChanged) {
          if (store != null) {
            await _prepare(store, id!, entry, e.info, fallbackSize: size);
          } else {
            entry.probed = null;
          }
        }
        if (!cancelled) {
          controller.addError(e, st);
          await controller.close();
        }
      } finally {
        for (final block in pending) {
          block.cancel();
        }
        pending.clear();
        _events?.send({
          'event': 'served',
          'start': start,
          'bytes': delivered,
          'firstMs': firstMs,
          'leadMs': leadMs,
          'totalMs': clock.elapsedMilliseconds,
          'splits': splits,
        });
      }
    }

    void wake() {
      resumed?.complete();
      resumed = null;
    }

    controller.onListen = () => unawaited(pump());
    controller.onResume = wake;
    controller.onCancel = () {
      cancelled = true;
      for (final block in pending) {
        block.cancel();
      }
      wake();
    };
    return controller.stream;
  }

  /// 同一条目的并发探测只请求一次
  Future<_UpstreamInfo?> _probeOnce(_Entry entry) =>
      entry.probing ??= _probe(entry).whenComplete(() => entry.probing = null);

  /// 探测文件大小、类型与校验信息
  Future<_UpstreamInfo?> _probe(_Entry entry) async {
    final upstream = await _openUpstream('GET', entry, 'bytes=0-0');
    if (upstream == null) return null;
    final info = _UpstreamInfo(upstream);
    await upstream.drain<void>().catchError((_) {});
    return info.usable ? info : null;
  }

  Future<void> _prepare(
    CacheStore store,
    String id,
    _Entry entry,
    _UpstreamInfo info, {
    int? fallbackSize,
  }) => store.prepare(
    id,
    size: info.size ?? fallbackSize!,
    contentType: info.contentType,
    etag: info.etag,
    lastModified: info.lastModified,
    filePath: entry.filePath,
    storageId: entry.storageId,
    serverId: entry.serverId,
    itemKey: entry.itemKey,
  );

  /// 第一个块小，尽快交付首字节（打开时读封装头、索引都是小读取）；之后都用 1 MiB，慢块交给动态分段切开。
  /// 实测（夸克冷门位置）每个请求首字节约 0.45 秒，小块爬坡（64 KiB → 256 KiB）拖动后拿到 8 MiB 要 6–8 秒，这样约 1.5 秒
  static int _blockSizeAt(int index) =>
      index == 0 ? 128 << 10 : 1 << 20;

  Future<Uint8List> _fetchBlock(
    _Entry entry,
    _Block block,
    int size,
    String? etag,
  ) async {
    final ticket = entry.slots.acquire(block.priority, block.index);
    block.ticket = ticket;
    await ticket.ready;
    _stats['peakBlocks'] = math.max(_stats['peakBlocks']!, ++_activeBlocks);
    try {
      if (block.cancelled) throw const _Cancelled();
      final upstream = await _openUpstream(
        'GET',
        entry,
        'bytes=${block.start}-${block.requestEnd - 1}',
      );
      if (upstream == null) throw const HttpException('upstream unavailable');
      final info = _UpstreamInfo(upstream);
      final changed =
          info.size != null && info.size != size ||
          info.etag != null && etag != null && info.etag != etag;
      if (changed ||
          info.status != HttpStatus.partialContent ||
          info.start != block.start) {
        await upstream.drain<void>().catchError((_) {});
        if (changed) throw _UpstreamChanged(info);
        throw HttpException('unexpected upstream status ${info.status}');
      }
      _count('blocks');
      return await block.read(upstream);
    } finally {
      _activeBlocks--;
      ticket.release();
    }
  }

  bool get _writable => _limit > 0;

  /// 有待配对的播放位置时，把这次读取的起点记为采样；文件首尾的读取（封装头、索引）不算
  void _recordStart(_Entry entry, String id, CacheStore store, int start) {
    final position = entry.pendingSampleMs;
    final size = store[id]?.size;
    if (position == null || size == null || _inPinZone(start, size)) return;
    entry.pendingSampleMs = null;
    if (position > 0) store.addSample(id, position, start);
  }

  /// 打开阶段把文件首尾的读取记为固定区间
  void _recordRead(_Entry entry, String id, CacheStore store, ByteRange read) {
    final until = entry.openingUntil;
    final size = store[id]?.size;
    if (until == null || size == null || read.isEmpty) return;
    if (DateTime.now().isAfter(until)) {
      entry.openingUntil = null;
      return;
    }
    if (read.start < _pinZone || read.end > size - _pinZone) {
      store.pin(id, read);
    }
  }

  bool _inPinZone(int offset, int size) =>
      offset < _pinZone || offset >= size - _pinZone;

  void _maybeEnforce(CacheStore store) {
    final now = DateTime.now();
    if (now.difference(_lastEnforce) < _enforceInterval) return;
    _lastEnforce = now;
    unawaited(
      store.enforce(_limit).catchError((Object _) => const EvictionPlan([], 0)),
    );
  }

  void _copyUpstreamHeaders(
    HttpClientResponse upstream,
    HttpResponse response,
  ) {
    response.statusCode = upstream.statusCode;
    for (final name in _forwardedHeaders) {
      final value = upstream.headers.value(name);
      if (value != null) response.headers.set(name, value);
    }
    if (upstream.contentLength >= 0) {
      response.contentLength = upstream.contentLength;
    }
  }

  /// 请求上游：401 / 403 / 410 / 412 时请主隔离区刷新一次地址（同一条目并发失效时只刷新一次）；
  /// 403 / 429 时退避重试。拿不到可用响应时返回 null
  Future<HttpClientResponse?> _openUpstream(
    String method,
    _Entry entry,
    String? range,
  ) async {
    final ready = await entry.upstreamReady.timeout(
      _upstreamTimeout,
      onTimeout: () => false,
    );
    if (!ready) return null;
    var refreshed = false;
    for (var attempt = 0; attempt < 4; attempt++) {
      final generation = entry.generation;
      final HttpClientResponse response;
      try {
        response = await _request(method, entry, range);
      } on IOException {
        if (attempt == 3) return null;
        await Future<void>.delayed(Duration(milliseconds: 300 << attempt));
        continue;
      }
      final status = response.statusCode;
      final expired =
          status == HttpStatus.unauthorized ||
          status == HttpStatus.forbidden ||
          status == HttpStatus.gone ||
          status == HttpStatus.preconditionFailed;
      if (expired && !refreshed && entry.refreshable) {
        refreshed = true;
        await response.drain<void>().catchError((_) {});
        if (await _refreshOnce(entry, generation)) continue;
        return null;
      }
      final throttled =
          status == HttpStatus.forbidden ||
          status == HttpStatus.tooManyRequests;
      if (throttled && attempt < 3) {
        await response.drain<void>().catchError((_) {});
        await Future<void>.delayed(Duration(milliseconds: 500 << attempt));
        continue;
      }
      return response;
    }
    return null;
  }

  /// 别的请求已经换过地址时直接重试；正在刷新时等它完成
  Future<bool> _refreshOnce(_Entry entry, int seenGeneration) {
    if (entry.generation != seenGeneration) return Future.value(true);
    return entry.refreshing ??= _refresh(
      entry,
    ).whenComplete(() => entry.refreshing = null);
  }

  Future<bool> _refresh(_Entry entry) async {
    final events = _events;
    if (events == null) return false;
    final reply = ReceivePort();
    events.send({'event': 'refresh', 'id': entry.id, 'reply': reply.sendPort});
    final result = await reply.first.timeout(
      const Duration(seconds: 20),
      onTimeout: () => null,
    );
    reply.close();
    if (result is! Map) return false;
    entry
      ..url = Uri.parse(result['url'] as String)
      ..headers = Map<String, String>.from(result['headers'] as Map)
      ..generation += 1;
    _count('refreshes');
    return true;
  }

  /// 手动跟随重定向：HttpClient 自动跟随时会丢掉自定义请求头。
  /// 跳到其他源时去掉 Authorization，避免把存储的凭据交给直链所在的主机
  Future<HttpClientResponse> _request(
    String method,
    _Entry entry,
    String? range,
  ) async {
    var url = entry.url!;
    var headers = entry.headers;
    for (var hop = 0; ; hop++) {
      final outgoing = await _client.openUrl(method, url)
        ..followRedirects = false;
      headers.forEach(outgoing.headers.set);
      if (range != null) outgoing.headers.set(HttpHeaders.rangeHeader, range);
      final response = await outgoing.close();
      final location = response.headers.value(HttpHeaders.locationHeader);
      if (!response.isRedirect || location == null || hop == 5) return response;
      await response.drain<void>();
      final next = url.resolve(location);
      if (next.scheme != url.scheme ||
          next.host != url.host ||
          next.port != url.port) {
        headers = {
          for (final e in headers.entries)
            if (e.key.toLowerCase() != 'authorization') e.key: e.value,
        };
      }
      url = next;
    }
  }

  /// 单段 Range，返回半开区间；不合法或越界时返回 null
  static (int, int)? _parseRange(String header, int size) {
    final match = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(header.trim());
    if (match == null || size <= 0) return null;
    final first = match.group(1)!;
    final last = match.group(2)!;
    if (first.isEmpty) {
      final suffix = int.tryParse(last);
      if (suffix == null || suffix <= 0) return null;
      return (math.max(0, size - suffix), size);
    }
    final start = int.parse(first);
    if (start >= size) return null;
    final end = last.isEmpty ? size : math.min(int.parse(last) + 1, size);
    return end <= start ? null : (start, end);
  }
}

/// 条目级连接配额：同一条目同时回源的请求不超过上限。
/// 等待时按请求序号从新到旧、同一请求内按块顺序分配
final class _Slots {
  _Slots(this._limit);

  final int Function() _limit;
  final List<_SlotTicket> _waiting = [];
  int _active = 0;

  _SlotTicket acquire(int priority, int order) {
    final ticket = _SlotTicket._(this, priority, order);
    if (_active < _limit()) {
      _active++;
      ticket._granted = true;
      ticket._ready.complete();
    } else {
      _waiting.add(ticket);
    }
    return ticket;
  }

  void _release(_SlotTicket ticket) {
    if (!ticket._granted) {
      _waiting.remove(ticket);
      return;
    }
    _active--;
    while (_active < _limit() && _waiting.isNotEmpty) {
      var best = _waiting.first;
      for (final t in _waiting) {
        if (t.priority > best.priority ||
            t.priority == best.priority && t.order < best.order) {
          best = t;
        }
      }
      _waiting.remove(best);
      _active++;
      best._granted = true;
      best._ready.complete();
    }
  }
}

final class _SlotTicket {
  _SlotTicket._(this._slots, this.priority, this.order);

  final _Slots _slots;
  final int priority;
  final int order;
  final Completer<void> _ready = Completer<void>();
  bool _granted = false;
  bool _released = false;

  Future<void> get ready => _ready.future;

  /// 归还连接；还在排队时取消排队。可重复调用
  void release() {
    if (_released) return;
    _released = true;
    _slots._release(this);
    if (!_ready.isCompleted) _ready.completeError(const _Cancelled());
  }
}

/// 并发回源的一个块。读取期间可以被切短（[shrinkTo]），后一半交给其他连接；
/// 收够新的长度就交付并断开上游
final class _Block {
  _Block(this.start, this.end, this.priority, this.index);

  final int start;
  int end;
  final int priority;
  final int index;
  late Future<Uint8List> result;
  _SlotTicket? ticket;
  StreamSubscription<List<int>>? _subscription;
  Completer<Uint8List>? _body;
  BytesBuilder? _builder;
  bool cancelled = false;
  bool done = false;

  /// 发起请求时的终点；之后被切短时不再重新请求，读到新终点即停
  late final int requestEnd = end;

  int get length => end - start;
  int get received => _builder?.length ?? 0;
  int get remaining => length - received;

  /// 剩余部分的中点
  int get splitPoint => start + received + remaining ~/ 2;

  /// 把终点提前到 [newEnd]；已经读到或越过新终点时立即交付。不能缩短时返回 false
  bool shrinkTo(int newEnd) {
    if (done || newEnd >= end || newEnd <= start + received) return false;
    end = newEnd;
    _completeIfFull();
    return true;
  }

  /// 读满整个块；多出的字节丢弃，提前结束时报错
  Future<Uint8List> read(HttpClientResponse upstream) {
    final body = _body = Completer<Uint8List>();
    final builder = _builder = BytesBuilder(copy: false);
    _subscription = upstream.listen(
      (chunk) {
        builder.add(chunk);
        _completeIfFull();
      },
      onDone: () {
        if (body.isCompleted) return;
        if (builder.length < length) {
          done = true;
          body.completeError(const HttpException('upstream ended early'));
        } else {
          _completeIfFull();
        }
      },
      onError: (Object e) {
        if (body.isCompleted) return;
        done = true;
        body.completeError(e);
      },
      cancelOnError: true,
    );
    if (cancelled) cancel();
    return body.future;
  }

  void _completeIfFull() {
    final body = _body;
    final builder = _builder;
    if (body == null || builder == null || body.isCompleted) return;
    if (builder.length < length) return;
    done = true;
    final bytes = builder.takeBytes();
    body.complete(
      bytes.length == length ? bytes : Uint8List.sublistView(bytes, 0, length),
    );
    final subscription = _subscription;
    _subscription = null;
    if (subscription != null) unawaited(subscription.cancel());
  }

  /// 只让排队中的块让出名额；已拿到连接的块在 [_CacheProxyServer._fetchBlock] 结束时归还，避免超出上限
  void cancel() {
    cancelled = true;
    done = true;
    final waiting = ticket;
    if (waiting != null && !waiting._granted) waiting.release();
    final subscription = _subscription;
    if (subscription == null) return;
    _subscription = null;
    unawaited(subscription.cancel());
    final body = _body;
    if (body != null && !body.isCompleted) {
      body.completeError(const _Cancelled());
    }
  }
}

final class _Cancelled implements Exception {
  const _Cancelled();
}

/// 回源时发现上游文件的大小或 ETag 变了
final class _UpstreamChanged implements Exception {
  _UpstreamChanged(this.info);

  final _UpstreamInfo info;
}
