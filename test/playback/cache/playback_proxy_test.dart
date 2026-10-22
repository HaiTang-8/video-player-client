import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/data/models/subtitle_info.dart';
import 'package:media_player/playback/cache/playback_proxy.dart';
import 'package:media_player/playback/cache/proxied_source_resolver.dart';
import 'package:media_player/playback/domain/playback_domain.dart';
import 'package:media_player/playback/session/playback_item.dart';
import 'package:media_player/playback/session/playback_source_resolver.dart';

import 'support/range_test_server.dart';

class _StaticResolver implements PlaybackSourceResolver {
  _StaticResolver(this.source);

  final PlaybackSource source;
  bool disposed = false;

  @override
  Future<ResolvedPlayback> resolve(PlaybackItem item) async =>
      ResolvedPlayback(source, storageId: 3, filePath: '/m/a.mkv');

  @override
  Future<String?> fetchSubtitleText(SubtitleInfo subtitle) async => 'sub';

  @override
  void dispose() => disposed = true;
}

void main() {
  late Directory dir;
  late RangeTestServer upstream;
  late PlaybackProxy proxy;
  late HttpClient client;
  final bytes = Uint8List.fromList(List.generate(4 << 20, (i) => i % 253));
  const auth = {'Authorization': 'Bearer t', 'User-Agent': 'player/1'};

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('proxy_test');
    final file = File('${dir.path}/a.mkv')..writeAsBytesSync(bytes);
    upstream = await RangeTestServer.start(file)
      ..requiredHeaders = auth;
    proxy = PlaybackProxy(watchLifecycle: false);
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

  test('forwards ranges with the registered headers', () async {
    final uri = await proxy.register(upstream.mediaUri, auth);
    expect(uri.host, '127.0.0.1');

    final (response, body) = await get(uri, range: 'bytes=100-199');
    expect(response.statusCode, HttpStatus.partialContent);
    expect(
      response.headers.value(HttpHeaders.contentRangeHeader),
      'bytes 100-199/${bytes.length}',
    );
    expect(response.headers.value(HttpHeaders.acceptRangesHeader), 'bytes');
    expect(body, bytes.sublist(100, 200));

    final (whole, all) = await get(uri);
    expect(whole.statusCode, HttpStatus.ok);
    expect(whole.contentLength, bytes.length);
    expect(all, bytes);
  });

  test('missing headers reach the upstream as they are', () async {
    final uri = await proxy.register(upstream.mediaUri, const {});
    final (response, _) = await get(uri, range: 'bytes=0-9');
    expect(response.statusCode, HttpStatus.unauthorized);
  });

  test('HEAD reports the upstream length without a body', () async {
    final uri = await proxy.register(upstream.mediaUri, auth);
    final (response, body) = await get(uri, method: 'HEAD');
    expect(response.statusCode, HttpStatus.ok);
    expect(response.contentLength, bytes.length);
    expect(body, isEmpty);
  });

  test('follows upstream redirects', () async {
    final uri = await proxy.register(upstream.redirectUri, auth);
    final (response, body) = await get(uri, range: 'bytes=0-9');
    expect(response.statusCode, HttpStatus.partialContent);
    expect(body, bytes.sublist(0, 10));
  });

  test('rejects unknown entries and foreign tokens', () async {
    final uri = await proxy.register(upstream.mediaUri, auth);
    final unknown = uri.replace(
      pathSegments: [...uri.pathSegments.take(2), '999'],
    );
    final foreign = uri.replace(
      pathSegments: ['bad', ...uri.pathSegments.skip(1)],
    );
    expect((await get(unknown)).$1.statusCode, HttpStatus.notFound);
    expect((await get(foreign)).$1.statusCode, HttpStatus.notFound);

    await proxy.unregister(uri);
    expect((await get(uri)).$1.statusCode, HttpStatus.notFound);
  });

  test('serves concurrent ranges of the same entry', () async {
    final uri = await proxy.register(upstream.mediaUri, auth);
    final results = await Future.wait([
      get(uri, range: 'bytes=0-1048575'),
      get(uri, range: 'bytes=2097152-3145727'),
    ]);
    expect(results[0].$2, bytes.sublist(0, 1 << 20));
    expect(results[1].$2, bytes.sublist(2 << 20, 3 << 20));
  });

  test('cancels the upstream when the player disconnects', () async {
    upstream.bytesPerSecond = 512 * 1024;
    final uri = await proxy.register(upstream.mediaUri, auth);
    final request = await client.getUrl(uri);
    final response = await request.close();
    final first = Completer<void>();
    late StreamSubscription<List<int>> sub;
    sub = response.listen((_) {
      if (!first.isCompleted) first.complete();
    });
    await first.future;
    await sub.cancel();
    client.close(force: true);

    for (
      var i = 0;
      i < 40 && !upstream.timeline.any((e) => e.contains('<'));
      i++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    final end = upstream.timeline.firstWhere((e) => e.contains('<'));
    final sentKiB = int.parse(
      RegExp(r'sent=(\d+)KiB').firstMatch(end)!.group(1)!,
    );
    expect(sentKiB, lessThan(bytes.length ~/ 1024 ~/ 2));
    expect((await proxy.stats())['cancelledUpstreams'], 1);
  });

  test('rebinds on the same port after the listener is lost', () async {
    final uri = await proxy.register(upstream.mediaUri, auth);
    await proxy.debugCloseListener();
    await expectLater(get(uri), throwsA(isA<SocketException>()));

    expect(await proxy.ensureListening(), isTrue);
    final (response, body) = await get(uri, range: 'bytes=0-9');
    expect(response.statusCode, HttpStatus.partialContent);
    expect(body, bytes.sublist(0, 10));
    expect(await proxy.ensureListening(), isTrue);
    expect((await proxy.stats())['rebinds'], 1, reason: '监听正常时不重新绑定');
  });

  test('resolver proxies network sources and keeps local files', () async {
    final network = _StaticResolver(
      PlaybackSource.network(upstream.mediaUri.toString(), httpHeaders: auth),
    );
    final resolver = ProxiedSourceResolver(network, proxy);
    final resolved = await resolver.resolve(const MoviePlaybackItem(1));
    expect(resolved.source.url, startsWith('http://127.0.0.1:'));
    expect(resolved.source.httpHeaders, isEmpty);
    expect(resolved.storageId, 3);
    expect(resolved.filePath, '/m/a.mkv');
    final (response, body) = await get(
      Uri.parse(resolved.source.url),
      range: 'bytes=0-9',
    );
    expect(response.statusCode, HttpStatus.partialContent);
    expect(body, bytes.sublist(0, 10));

    resolver.dispose();
    expect(network.disposed, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(
      (await get(Uri.parse(resolved.source.url))).$1.statusCode,
      HttpStatus.notFound,
    );

    final local = ProxiedSourceResolver(
      _StaticResolver(const PlaybackSource.localFile('/movies/a.mkv')),
      proxy,
    );
    final file = await local.resolve(const MoviePlaybackItem(1));
    expect(file.source.url, '/movies/a.mkv');
  });
}
