import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/data/models/stream_link.dart';
import 'package:media_player/data/models/subtitle_info.dart';
import 'package:media_player/playback/cache/playback_proxy.dart';
import 'package:media_player/playback/cache/proxied_source_resolver.dart';
import 'package:media_player/playback/domain/playback_domain.dart';
import 'package:media_player/playback/session/playback_item.dart';
import 'package:media_player/playback/session/playback_source_resolver.dart';

import 'support/range_test_server.dart';

/// 可控的内层解析器：[gate] 未完成时卡住，模拟流地址 API + 302 解析
class _GatedResolver implements PlaybackSourceResolver {
  _GatedResolver(this.url);

  Uri url;
  String filePath = '/movies/a.mkv';
  Object? error;
  Completer<void>? gate;
  int calls = 0;
  StreamLinkKind? kind;
  int connections = 1;
  Map<String, String> Function(int call) headers = (_) => const {};
  final List<({String? variant, bool fresh})> requests = [];

  @override
  Future<ResolvedPlayback> resolve(
    PlaybackItem item, {
    String? variant,
    bool fresh = false,
  }) async {
    calls++;
    requests.add((variant: variant, fresh: fresh));
    await gate?.future;
    final failure = error;
    if (failure != null) throw failure;
    return ResolvedPlayback(
      PlaybackSource.network(url.toString(), httpHeaders: headers(calls)),
      storageId: 3,
      filePath: filePath,
      linkKind: kind,
      variant: kind == null ? null : variant ?? StreamLink.originalVariant,
      maxConnections: connections,
    );
  }

  @override
  Future<String?> fetchSubtitleText(SubtitleInfo subtitle) async => null;

  @override
  void dispose() {}
}

void main() {
  const size = 2 << 20;
  const movie = MoviePlaybackItem(7);
  final bytes = Uint8List.fromList(List.generate(size, (i) => (i * 13) % 241));
  late Directory dir;
  late RangeTestServer upstream;
  late PlaybackProxy proxy;
  late _GatedResolver inner;
  late HttpClient client;
  String? downloaded;

  ProxiedSourceResolver resolver() => ProxiedSourceResolver(
    inner,
    proxy,
    serverUrl: () => 'http://media.local:5681',
    findDownloadedFile: (_) async => downloaded,
  );

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('proxied_resolver_test');
    final file = File('${dir.path}/a.mkv')..writeAsBytesSync(bytes);
    upstream = await RangeTestServer.start(file);
    proxy = PlaybackProxy(
      watchLifecycle: false,
      cacheDirectory: () async => Directory('${dir.path}/cache'),
      blockSize: 64 * 1024,
    );
    inner = _GatedResolver(upstream.mediaUri);
    downloaded = null;
    client = HttpClient()..findProxy = (_) => 'DIRECT';
  });

  tearDown(() async {
    client.close(force: true);
    await upstream.close();
    await dir.delete(recursive: true);
  });

  Future<List<int>> read(String url, String range) async {
    final request = await client.getUrl(Uri.parse(url));
    request.headers.set(HttpHeaders.rangeHeader, range);
    final response = await request.close();
    return response.fold<List<int>>([], (a, b) => a..addAll(b));
  }

  /// 第一次正常解析并缓存开头 256KiB
  Future<void> warmUp() async {
    final first = await resolver().resolve(movie);
    await read(first.source.url, 'bytes=0-262143');
    expect(inner.calls, 1);
  }

  test('a cached item opens before the upstream is resolved', () async {
    await warmUp();
    inner.gate = Completer<void>();

    final resolved = await resolver().resolve(movie);
    expect(resolved.source.url, startsWith('http://127.0.0.1:'));
    expect(resolved.filePath, '/movies/a.mkv');
    expect(resolved.storageId, 3);
    expect(resolved.observer, isNotNull);

    upstream.resetStats();
    expect(
      await read(resolved.source.url, 'bytes=0-99999'),
      bytes.sublist(0, 100000),
    );
    expect(upstream.requestCount, 0, reason: '已缓存的部分不等上游');

    final gap = read(resolved.source.url, 'bytes=500000-599999');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(upstream.requestCount, 0, reason: '回源要等后台解析完成');
    inner.gate!.complete();
    expect(await gap, bytes.sublist(500000, 600000));
    expect(inner.calls, 2);
  });

  test('a downloaded file wins over the cache', () async {
    await warmUp();
    downloaded = '/downloads/a.mkv';
    inner.gate = Completer<void>()..complete();
    await resolver().resolve(movie);
    expect(inner.calls, 2, reason: '有本地文件时照常走内层解析器');
  });

  test('a changed source drops the stale cache', () async {
    await warmUp();
    inner.filePath = '/movies/a-remux.mkv';

    final resolved = await resolver().resolve(movie);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(await proxy.entries(), isEmpty);

    var length = -1;
    try {
      length = (await read(resolved.source.url, 'bytes=0-99')).length;
    } on IOException {
      length = 0;
    }
    expect(length, lessThan(100));
  });

  test('a failed background resolve still serves the cache', () async {
    await warmUp();
    inner.error = const SocketException('offline');

    final resolved = await resolver().resolve(movie);
    expect(
      await read(resolved.source.url, 'bytes=1000-1999'),
      bytes.sublist(1000, 2000),
    );

    var length = -1;
    try {
      length = (await read(resolved.source.url, 'bytes=900000-999999')).length;
    } on IOException {
      length = 0;
    }
    expect(length, lessThan(100000), reason: '缺口无法回源');
  });

  test('items without cache go through the normal path', () async {
    final resolved = await resolver().resolve(const MoviePlaybackItem(8));
    expect(inner.calls, 1);
    expect(await read(resolved.source.url, 'bytes=0-9'), bytes.sublist(0, 10));
  });

  test(
    'with the cache off only direct file links go through the proxy',
    () async {
      final noCache = ProxiedSourceResolver(
        inner,
        proxy,
        cacheEnabled: false,
        serverUrl: () => 'http://media.local:5681',
      );
      final plain = await noCache.resolve(movie);
      expect(plain.source.url, upstream.mediaUri.toString());

      inner
        ..kind = StreamLinkKind.file
        ..connections = 4;
      final direct = await noCache.resolve(movie);
      expect(Uri.parse(direct.source.url).host, '127.0.0.1');
      expect(direct.maxConnections, 4);
      expect(
        await read(direct.source.url, 'bytes=0-99'),
        bytes.sublist(0, 100),
      );
      expect((await proxy.usage())['bytes'], 0);
    },
  );

  test('hls links are handed to the engine directly', () async {
    inner.kind = StreamLinkKind.hls;
    final resolved = await resolver().resolve(movie, variant: '4k');
    expect(resolved.source.url, upstream.mediaUri.toString());
    expect(inner.requests.single, (variant: '4k', fresh: false));
  });

  test(
    'a rejected direct link is refreshed with fresh and its variant',
    () async {
      upstream.requiredHeaders = const {'Cookie': '__puus=new'};
      inner
        ..kind = StreamLinkKind.file
        ..connections = 2
        ..headers =
            (call) => {'Cookie': call == 1 ? '__puus=old' : '__puus=new'};
      final resolved = await resolver().resolve(movie);
      expect(
        await read(resolved.source.url, 'bytes=0-99'),
        bytes.sublist(0, 100),
      );
      expect(inner.requests.last, (
        variant: StreamLink.originalVariant,
        fresh: true,
      ));
    },
  );
}
