import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/playback/cache/playback_proxy.dart';

import 'support/range_test_server.dart';

/// 多连接回源（网盘单连接限速）：分块并发、按序交付、连接配额、取消、412 只刷新一次、缓存写盘
void main() {
  const size = 3 << 20;
  const cookie = {'Cookie': '__puus=ok'};
  final bytes = Uint8List.fromList(
    List.generate(size, (i) => (i * 31 + 7) % 253),
  );
  late Directory dir;
  late File file;
  late RangeTestServer upstream;
  late HttpClient client;

  PlaybackProxy newProxy({int quota = 0}) => PlaybackProxy(
    watchLifecycle: false,
    cacheDirectory: () async => Directory('${dir.path}/cache'),
    quotaBytes: quota,
    blockSize: 64 * 1024,
  );

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('cache_proxy_parallel_test');
    file = File('${dir.path}/a.mp4')..writeAsBytesSync(bytes);
    upstream =
        await RangeTestServer.start(file)
          ..requiredHeaders = cookie
          ..rejectStatus = HttpStatus.preconditionFailed;
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

  List<String> mediaGets() =>
      upstream.requestLog.where((l) => l.startsWith('GET')).toList();

  test(
    'pass-through ranges are assembled in order from parallel blocks',
    () async {
      final proxy = newProxy();
      final uri = await proxy.register(
        upstream.mediaUri,
        cookie,
        maxConnections: 6,
      );

      final (partial, body) = await get(uri, range: 'bytes=100-${size - 78}');
      expect(partial.statusCode, HttpStatus.partialContent);
      expect(
        partial.headers.value(HttpHeaders.contentRangeHeader),
        'bytes 100-${size - 78}/$size',
      );
      expect(body, bytes.sublist(100, size - 77));
      expect((await proxy.stats())['peakBlocks'], inInclusiveRange(2, 6));

      final (full, all) = await get(uri);
      expect(full.statusCode, HttpStatus.ok);
      expect(full.contentLength, size);
      expect(all, bytes);

      final (head, headBody) = await get(uri, method: 'HEAD');
      expect(head.contentLength, size);
      expect(head.headers.value(HttpHeaders.acceptRangesHeader), 'bytes');
      expect(headBody, isEmpty);

      final (invalid, _) = await get(uri, range: 'bytes=$size-');
      expect(invalid.statusCode, HttpStatus.requestedRangeNotSatisfiable);
    },
  );

  test(
    'throughput scales with connections under a per-connection limit',
    () async {
      upstream.bytesPerSecond = 512 * 1024;
      final proxy = newProxy();
      final uri = await proxy.register(
        upstream.mediaUri,
        cookie,
        maxConnections: 8,
      );

      final watch = Stopwatch()..start();
      final (_, body) = await get(uri);
      watch.stop();
      expect(body, bytes);
      // 单连接需要 6 秒；并发（128 KiB 首块 + 3 个 1 MiB 块）约 2 秒
      expect(watch.elapsed, lessThan(const Duration(seconds: 4)));
      expect((await proxy.stats())['peakBlocks'], greaterThanOrEqualTo(3));
    },
  );

  test('concurrent player requests share the connection quota', () async {
    upstream.bytesPerSecond = 512 * 1024;
    final proxy = newProxy();
    final uri = await proxy.register(
      upstream.mediaUri,
      cookie,
      maxConnections: 4,
    );

    final results = await Future.wait([
      get(uri, range: 'bytes=0-${(1 << 20) - 1}'),
      get(uri, range: 'bytes=${size - (1 << 20)}-'),
    ]);
    expect(results[0].$2, bytes.sublist(0, 1 << 20));
    expect(results[1].$2, bytes.sublist(size - (1 << 20)));
    expect((await proxy.stats())['peakBlocks'], 4);
    expect(mediaGets().where((l) => l.contains('bytes=0-0')), hasLength(1));
  });

  test('a player disconnect cancels in-flight blocks', () async {
    upstream.bytesPerSecond = 64 * 1024;
    final proxy = newProxy();
    final uri = await proxy.register(
      upstream.mediaUri,
      cookie,
      maxConnections: 4,
    );

    final request = await client.openUrl('GET', uri);
    final response = await request.close();
    final first = Completer<void>();
    late StreamSubscription<List<int>> sub;
    sub = response.listen((_) {
      if (!first.isCompleted) first.complete();
    });
    await first.future;
    expect(upstream.active, greaterThan(0));
    await sub.cancel();
    client.close(force: true);

    final deadline = DateTime.now().add(const Duration(seconds: 3));
    while (upstream.active > 0 && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(upstream.active, 0);
    client = HttpClient()..findProxy = (_) => 'DIRECT';
  });

  test('many blocks rejected with 412 trigger a single refresh', () async {
    final proxy = newProxy();
    var refreshes = 0;
    final uri = await proxy.register(
      upstream.mediaUri,
      cookie,
      maxConnections: 8,
      refresh: () async {
        refreshes++;
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return (url: upstream.mediaUri, headers: {'Cookie': '__puus=new'});
      },
    );
    final (_, warm) = await get(uri, range: 'bytes=0-9');
    expect(warm, bytes.sublist(0, 10));

    upstream.requiredHeaders = const {'Cookie': '__puus=new'};
    final (response, body) = await get(uri, range: 'bytes=0-${(1 << 20) - 1}');
    expect(response.statusCode, HttpStatus.partialContent);
    expect(body, bytes.sublist(0, 1 << 20));
    expect(refreshes, 1);
    expect((await proxy.stats())['refreshes'], 1);
  });

  test(
    'cached entries probe the size, fetch gaps in parallel and reuse the disk',
    () async {
      final proxy = newProxy(quota: 1 << 30);
      final uri = await proxy.register(
        upstream.mediaUri,
        cookie,
        cacheId: 'p',
        maxConnections: 6,
      );

      final (first, body) = await get(uri, range: 'bytes=0-${(1 << 20) - 1}');
      expect(first.statusCode, HttpStatus.partialContent);
      expect(body, bytes.sublist(0, 1 << 20));
      expect(mediaGets().first, contains('bytes=0-0'));
      expect((await proxy.stats())['peakBlocks'], greaterThan(1));

      await proxy.flush();
      upstream.resetStats();
      final (_, again) = await get(uri, range: 'bytes=4096-${(1 << 20) - 1}');
      expect(again, bytes.sublist(4096, 1 << 20));
      expect(mediaGets(), isEmpty);
    },
  );

  test('a changed upstream file fails the response and is re-probed', () async {
    final proxy = newProxy();
    final uri = await proxy.register(
      upstream.mediaUri,
      cookie,
      maxConnections: 4,
    );
    final (_, before) = await get(uri, range: 'bytes=0-99');
    expect(before, bytes.sublist(0, 100));

    final changed = Uint8List.fromList(
      List.generate(size + 1000, (i) => i % 7),
    );
    file.writeAsBytesSync(changed);
    var length = -1;
    try {
      length = (await get(uri, range: 'bytes=0-${(256 << 10) - 1}')).$2.length;
    } on IOException {
      length = 0;
    }
    expect(length, lessThan(256 << 10));

    final (after, body) = await get(uri, range: 'bytes=${size + 900}-');
    expect(
      after.headers.value(HttpHeaders.contentRangeHeader),
      'bytes ${size + 900}-${size + 999}/${size + 1000}',
    );
    expect(body, changed.sublist(size + 900));
  });
  group('dynamic segmentation', () {
    // 首块 128 KiB，之后每块 1 MiB；从 1152 KiB 开始的块首字节慢、速度也慢（实测冷门位置的典型表现）
    const slowStart = 1152 << 10;
    const slowRate = 128 * 1024;

    void slowBlock() {
      upstream
        ..bytesPerSecondFor = ((start) => start == slowStart ? slowRate : null)
        ..firstByteLatencyFor =
            ((start) => start == slowStart ? const Duration(seconds: 1) : null);
    }

    test('a slow block is split across idle connections', () async {
      slowBlock();
      final proxy = newProxy();
      final uri = await proxy.register(
        upstream.mediaUri,
        cookie,
        maxConnections: 4,
      );

      final watch = Stopwatch()..start();
      final (_, body) = await get(uri, range: 'bytes=0-');
      watch.stop();
      expect(body, bytes);
      // 不切分时这个块要 1 + 1 MiB ÷ 128 KiB/s = 9 秒；后一半交给空闲连接后约 5 秒
      expect(watch.elapsed, lessThan(const Duration(seconds: 7)));
      final stats = await proxy.stats();
      expect(stats['splits'], greaterThan(0));
      expect(stats['peakBlocks'], lessThanOrEqualTo(4));
    });

    test('split blocks are written to the cache in order', () async {
      slowBlock();
      final proxy = newProxy(quota: 64 << 20);
      final uri = await proxy.register(
        upstream.mediaUri,
        cookie,
        cacheId: 'split',
        maxConnections: 4,
      );

      final (_, first) = await get(uri, range: 'bytes=0-');
      expect(first, bytes);
      expect((await proxy.stats())['splits'], greaterThan(0));

      final requests = upstream.requestCount;
      final (_, again) = await get(uri, range: 'bytes=0-');
      expect(again, bytes);
      expect(upstream.requestCount, requests, reason: '第二次全部从缓存读取');
    });

    test('a disconnect during a split cancels every piece', () async {
      slowBlock();
      final proxy = newProxy();
      final uri = await proxy.register(
        upstream.mediaUri,
        cookie,
        maxConnections: 4,
      );

      final request = await client.openUrl('GET', uri);
      final response = await request.close();
      final sub = response.listen((_) {});
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (((await proxy.stats())['splits'] ?? 0) == 0 &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect((await proxy.stats())['splits'], greaterThan(0));
      await sub.cancel();
      client.close(force: true);

      final idle = DateTime.now().add(const Duration(seconds: 3));
      while (upstream.active > 0 && DateTime.now().isBefore(idle)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(upstream.active, 0);
      client = HttpClient()..findProxy = (_) => 'DIRECT';
    });
  });
}
