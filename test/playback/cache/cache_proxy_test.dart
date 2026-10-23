import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/playback/cache/playback_proxy.dart';

import 'support/range_test_server.dart';

/// 经过磁盘缓存的代理：命中读盘、缺口回源并写入、文件变化作废、刷新上游地址、固定区间与采样
void main() {
  const blockSize = 64 * 1024;
  const size = 4 << 20;
  const auth = {'Authorization': 'Bearer t'};
  final bytes = Uint8List.fromList(
    List.generate(size, (i) => (i * 7 + 3) % 251),
  );
  late Directory dir;
  late File file;
  late RangeTestServer upstream;
  late PlaybackProxy proxy;
  late HttpClient client;

  PlaybackProxy newProxy({int quota = 1 << 30}) => PlaybackProxy(
    watchLifecycle: false,
    cacheDirectory: () async => Directory('${dir.path}/cache'),
    quotaBytes: quota,
    blockSize: blockSize,
  );

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('cache_proxy_test');
    file = File('${dir.path}/a.mkv')..writeAsBytesSync(bytes);
    upstream = await RangeTestServer.start(file)
      ..requiredHeaders = auth;
    proxy = newProxy();
    // 开发机上的 HTTP_PROXY 环境变量不排除本机地址
    client = HttpClient()..findProxy = (_) => 'DIRECT';
  });

  tearDown(() async {
    client.close(force: true);
    await upstream.close();
    await dir.delete(recursive: true);
  });

  Future<(HttpClientResponse, List<int>)> get(
    Uri uri, {
    String? range,
    String method = 'GET',
  }) async {
    final request = await client.openUrl(method, uri);
    if (range != null) request.headers.set(HttpHeaders.rangeHeader, range);
    final response = await request.close();
    final body = await response.fold<List<int>>([], (a, b) => a..addAll(b));
    return (response, body);
  }

  Future<Uri> register(String cacheId, {UpstreamRefresher? refresh}) => proxy
      .register(upstream.mediaUri, auth, cacheId: cacheId, refresh: refresh);

  List<String> mediaGets() =>
      upstream.requestLog.where((l) => l.startsWith('GET')).toList();

  test('a second read is served from disk without the upstream', () async {
    final uri = await register('a');
    final (cold, first) = await get(uri, range: 'bytes=0-999999');
    expect(cold.statusCode, HttpStatus.partialContent);
    expect(first, bytes.sublist(0, 1000000));

    upstream.resetStats();
    final (warm, second) = await get(uri, range: 'bytes=100-899999');
    expect(warm.statusCode, HttpStatus.partialContent);
    expect(
      warm.headers.value(HttpHeaders.contentRangeHeader),
      'bytes 100-899999/$size',
    );
    expect(second, bytes.sublist(100, 900000));
    expect(upstream.requestCount, 0);
    expect((await proxy.stats())['cacheBytes'], 899900);
  });

  test('only the gaps of a partly cached range go to the upstream', () async {
    final uri = await register('a');
    await get(uri, range: 'bytes=1048576-2097151');
    upstream.resetStats();

    final (_, body) = await get(uri, range: 'bytes=0-3145727');
    expect(body, bytes.sublist(0, 3145728));
    expect(mediaGets(), [
      'GET /media/a.mkv bytes=0-1048575',
      'GET /media/a.mkv bytes=2097152-3145727',
    ]);
  });

  test('open-ended and suffix ranges use the cached size', () async {
    final uri = await register('a');
    await get(uri, range: 'bytes=0-');
    upstream.resetStats();

    final (tail, body) = await get(uri, range: 'bytes=-1000');
    expect(
      tail.headers.value(HttpHeaders.contentRangeHeader),
      'bytes ${size - 1000}-${size - 1}/$size',
    );
    expect(body, bytes.sublist(size - 1000));
    final (whole, all) = await get(uri);
    expect(whole.statusCode, HttpStatus.ok);
    expect(all, bytes);
    expect(upstream.requestCount, 0);

    final (bad, _) = await get(uri, range: 'bytes=$size-');
    expect(bad.statusCode, HttpStatus.requestedRangeNotSatisfiable);
  });

  test('cached data stays readable when the upstream is gone', () async {
    final uri = await register('a');
    await get(uri, range: 'bytes=0-524287');
    await upstream.close();

    final (head, _) = await get(uri, method: 'HEAD');
    expect(head.contentLength, size);
    final (cached, body) = await get(uri, range: 'bytes=1000-499999');
    expect(cached.statusCode, HttpStatus.partialContent);
    expect(body, bytes.sublist(1000, 500000));

    // 响应头已按缓存发出，缺口回源失败时连接提前结束
    var missing = -1;
    try {
      missing = (await get(uri, range: 'bytes=600000-699999')).$2.length;
    } on IOException {
      missing = 0;
    }
    expect(missing, lessThan(100000));
  });

  test('a changed upstream file invalidates the cache', () async {
    final uri = await register('a');
    await get(uri, range: 'bytes=0-262143');
    expect((await proxy.usage())['bytes'], 262144);

    await file.setLastModified(DateTime(2030));
    try {
      await get(uri, range: 'bytes=0-524287');
    } catch (_) {}
    expect((await proxy.usage())['bytes'], lessThan(262144), reason: '旧数据作废');

    final (_, body) = await get(uri, range: 'bytes=0-524287');
    expect(body, bytes.sublist(0, 524288));
  });

  test('an expired upstream address is refreshed once', () async {
    upstream.requiredHeaders = const {'Authorization': 'Bearer new'};
    var refreshes = 0;
    final uri = await register(
      'a',
      refresh: () async {
        refreshes++;
        return (
          url: upstream.mediaUri,
          headers: {'Authorization': 'Bearer new'},
        );
      },
    );
    final (response, body) = await get(uri, range: 'bytes=0-9');
    expect(response.statusCode, HttpStatus.partialContent);
    expect(body, bytes.sublist(0, 10));
    expect(refreshes, 1);
    expect((await proxy.stats())['refreshes'], 1);
  });

  test('a smaller quota evicts and clearing empties the cache', () async {
    final uri = await register('a');
    await get(uri, range: 'bytes=0-2097151');
    expect((await proxy.usage())['bytes'], 2097152);

    await proxy.setQuota(1 << 20);
    expect((await proxy.usage())['bytes'], 0, reason: '没有续播集的条目整条删除');

    await proxy.setQuota(1 << 30);
    await get(uri, range: 'bytes=0-65535');
    await proxy.clearCache();
    expect((await proxy.usage())['entries'], 0);
  });

  test('entries list cached videos by file name and can be removed', () async {
    final uri = await proxy.register(
      upstream.mediaUri,
      auth,
      cacheId: 'a',
      filePath: '/movies/A Movie (2026).mkv',
      storageId: 3,
    );
    await get(uri, range: 'bytes=0-131071');
    final second = await proxy.register(
      upstream.redirectUri,
      auth,
      cacheId: 'b',
    );
    await get(second, range: 'bytes=0-65535');

    final entries = await proxy.entries();
    expect(entries.map((e) => e.name), ['b', 'A Movie (2026).mkv']);
    expect(entries.last.cachedBytes, 131072);
    expect(entries.last.sizeBytes, size);
    expect(entries.last.complete, isFalse);
    expect(await proxy.usedBytes(), 131072 + 65536);

    await proxy.remove('a');
    expect((await proxy.entries()).map((e) => e.id), ['b']);
    expect(await proxy.usedBytes(), 65536);
  });

  test('a zero quota passes through without writing', () async {
    proxy = newProxy(quota: 0);
    final uri = await register('a');
    final (_, body) = await get(uri, range: 'bytes=0-99');
    expect(body, bytes.sublist(0, 100));
    expect((await proxy.usage())['bytes'], 0);
  });

  test('a player disconnect keeps the whole blocks it received', () async {
    upstream.bytesPerSecond = 2 << 20;
    final uri = await register('a');
    final request = await client.getUrl(uri);
    request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-');
    final response = await request.close();
    var received = 0;
    final enough = Completer<void>();
    late StreamSubscription<List<int>> sub;
    sub = response.listen((chunk) {
      received += chunk.length;
      if (received >= 300 * 1024 && !enough.isCompleted) enough.complete();
    });
    await enough.future;
    await sub.cancel();
    client.close(force: true);
    client = HttpClient()..findProxy = (_) => 'DIRECT';
    await Future<void>.delayed(const Duration(milliseconds: 300));

    final cached = (await proxy.usage())['bytes']!;
    expect(cached, greaterThanOrEqualTo(4 * blockSize));
    expect(cached, lessThan(size ~/ 2), reason: '断开后不再回源');
    expect(
      upstream.timeline.any((e) => e.startsWith('+') && e.contains('<')),
      isTrue,
    );
  });

  test('opening pins the head and tail and seeks record samples', () async {
    final big = File('${dir.path}/big.mkv');
    const bigSize = 200 << 20;
    final raf = await big.open(mode: FileMode.write);
    await raf.setPosition(bigSize - 1);
    await raf.writeByte(1);
    await raf.close();
    final server = await RangeTestServer.start(big);
    addTearDown(server.close);
    final uri = await proxy.register(server.mediaUri, const {}, cacheId: 'big');

    proxy.opening(uri, const Duration(minutes: 10));
    await get(uri, range: 'bytes=-65536');
    await get(uri, range: 'bytes=0-131071');
    await get(uri, range: 'bytes=104857600-104923135');
    proxy.opened(uri);
    await get(uri, range: 'bytes=${bigSize - 200000}-${bigSize - 100001}');
    proxy
      ..seek(uri, const Duration(minutes: 20))
      ..progress(uri, const Duration(minutes: 20), const Duration(hours: 1));
    // 中间区域是 [64MiB, 136MiB)，首尾 64MiB 内的读取不作为采样
    await get(uri, range: 'bytes=115343360-115408895');
    await proxy.flush();

    final meta =
        jsonDecode(await File('${dir.path}/cache/big/meta.json').readAsString())
            as Map<String, Object?>;
    expect(meta['pinned'], [
      [0, 131072],
      [bigSize - 65536, bigSize],
    ], reason: '打开期间只固定文件首尾；中间的续播点和打开后的读取不固定');
    expect(meta['samples'], [
      [600000, 104857600],
      [1200000, 115343360],
    ]);
    expect(meta['resumePositionMs'], 1200000);
    expect(meta['durationMs'], 3600000);
  });
}
