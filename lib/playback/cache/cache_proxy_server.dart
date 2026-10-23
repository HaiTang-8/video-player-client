import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

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
  }) {
    if (url != null) _upstream.complete(true);
  }

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
  };

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

  /// 请求上游：401 / 403 / 410 时请主隔离区刷新一次地址；403 / 429 时退避重试。
  /// 拿不到可用响应时返回 null
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
          status == HttpStatus.gone;
      if (expired && !refreshed && entry.refreshable) {
        refreshed = true;
        await response.drain<void>().catchError((_) {});
        if (await _refresh(entry)) continue;
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
      ..headers = Map<String, String>.from(result['headers'] as Map);
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
