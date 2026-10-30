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
      upstream.bytesPerSecond = 128 * 1024;
      final proxy = newProxy();
      final uri = await proxy.register(
        upstream.mediaUri,
        cookie,
        maxConnections: 8,
      );

      final watch = Stopwatch()..start();
      final (_, body) = await get(uri, range: 'bytes=0-${(512 << 10) - 1}');
      watch.stop();
      expect(body, bytes.sublist(0, 512 << 10));
      // 单连接需要 4 秒；8 个连接并发应明显更快
      expect(watch.elapsed, lessThan(const Duration(milliseconds: 2000)));
      expect((await proxy.stats())['peakBlocks'], greaterThanOrEqualTo(6));
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
}
