import 'dart:async';
import 'dart:io';
import 'dart:isolate';

/// 代理隔离区的入口参数
final class CacheProxyBoot {
  const CacheProxyBoot(this.reply, this.token);

  final SendPort reply;
  final String token;
}

/// 代理隔离区：只监听本机回环地址，按 Range 透传到上游（Stage 2 Spike，不写盘）
///
/// 用 addStream 转发：播放器读得慢时上游读取也随之变慢；播放器断开后，
/// 下一次写入失败时会取消上游订阅并关闭上游连接
Future<void> cacheProxyMain(CacheProxyBoot boot) async {
  final server = _CacheProxyServer(boot.token);
  final commands = ReceivePort();
  final port = await server.bind();
  boot.reply.send(<String, Object>{
    'port': port,
    'commands': commands.sendPort,
  });
  await for (final message in commands) {
    final map = message as Map<String, Object?>;
    final reply = map['reply'] as SendPort?;
    reply?.send(await server.command(map));
  }
}

class _Entry {
  _Entry(this.url, this.headers);

  final Uri url;
  final Map<String, String> headers;
}

class _CacheProxyServer {
  _CacheProxyServer(this._token);

  static const _forwardedHeaders = [
    HttpHeaders.contentTypeHeader,
    HttpHeaders.contentRangeHeader,
    HttpHeaders.acceptRangesHeader,
    HttpHeaders.etagHeader,
    HttpHeaders.lastModifiedHeader,
  ];

  final String _token;
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
  int _requests = 0;
  int _bytes = 0;
  int _active = 0;
  int _cancelledUpstreams = 0;
  int _rebinds = 0;

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
    switch (message['cmd']) {
      case 'register':
        _entries[message['id'] as String] = _Entry(
          Uri.parse(message['url'] as String),
          Map<String, String>.from(message['headers'] as Map),
        );
        return true;
      case 'unregister':
        _entries.remove(message['id']);
        return true;
      case 'ensure':
        return _ensureListening();
      case 'closeListener':
        await _server?.close(force: true);
        _server = null;
        return true;
      case 'stats':
        return <String, int>{
          'requests': _requests,
          'bytes': _bytes,
          'active': _active,
          'cancelledUpstreams': _cancelledUpstreams,
          'rebinds': _rebinds,
        };
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
        _rebinds++;
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

  Future<void> _handle(HttpRequest request) async {
    _requests++;
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

    _active++;
    HttpClientResponse? upstream;
    var finished = false;
    try {
      upstream = await _openUpstream(
        request.method,
        entry,
        request.headers.value(HttpHeaders.rangeHeader),
      );

      response.statusCode = upstream.statusCode;
      for (final name in _forwardedHeaders) {
        final value = upstream.headers.value(name);
        if (value != null) response.headers.set(name, value);
      }
      if (upstream.contentLength >= 0) {
        response.contentLength = upstream.contentLength;
      }
      if (request.method == 'HEAD') {
        await upstream.drain<void>();
        finished = true;
        await response.close();
        return;
      }
      var forwarded = 0;
      await response.addStream(
        upstream.map((chunk) {
          forwarded += chunk.length;
          _bytes += chunk.length;
          return chunk;
        }),
      );
      // 播放器断开时 addStream 会在下一次写入时结束并取消上游，但不会报错
      if (upstream.contentLength >= 0 && forwarded < upstream.contentLength) {
        _cancelledUpstreams++;
      }
      finished = true;
      await response.close();
    } catch (_) {
      if (upstream == null) {
        try {
          response.statusCode = HttpStatus.badGateway;
        } catch (_) {}
      } else if (!finished) {
        _cancelledUpstreams++;
      }
      await response.close().catchError((_) {});
    } finally {
      _active--;
    }
  }

  /// 手动跟随重定向：HttpClient 自动跟随时会丢掉自定义请求头。
  /// 跳到其他源时去掉 Authorization，避免把存储的凭据交给直链所在的主机
  Future<HttpClientResponse> _openUpstream(
    String method,
    _Entry entry,
    String? range,
  ) async {
    var url = entry.url;
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
}
