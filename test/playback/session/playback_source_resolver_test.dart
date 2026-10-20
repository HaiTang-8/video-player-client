import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/core/utils/http_utils.dart';
import 'package:media_player/data/models/storage.dart';
import 'package:media_player/data/models/stream_info.dart';
import 'package:media_player/data/services/download_service.dart';
import 'package:media_player/playback/session/playback_item.dart';
import 'package:media_player/playback/session/playback_source_resolver.dart';

import '../fakes/fake_gateways.dart';

class _HeadAdapter implements HttpClientAdapter {
  _HeadAdapter({this.location});

  final String? location;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final target = location;
    if (target == null) return ResponseBody.fromString('', 200);
    return ResponseBody.fromString(
      '',
      302,
      headers: {
        'location': [target],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  const movie = MoviePlaybackItem(7);
  late FakeSourceGateway gateway;

  setUp(() => gateway = FakeSourceGateway());

  PlaybackSourceResolver resolver(_HeadAdapter adapter) =>
      PlaybackSourceResolver(gateway, dio: Dio()..httpClientAdapter = adapter);

  test('prefers downloaded file', () async {
    gateway.downloadedFile = '/downloads/movie.mkv';
    final adapter = _HeadAdapter();
    final resolved = await resolver(adapter).resolve(movie);

    expect(resolved.source.isLocalFile, isTrue);
    expect(resolved.source.url, '/downloads/movie.mkv');
    expect(gateway.streamRequests, isEmpty);
    expect(adapter.requests, isEmpty);
  });

  test('throws when no stream url is available', () async {
    gateway.streamInfo = StreamInfo(url: '');
    expect(
      resolver(_HeadAdapter()).resolve(movie),
      throwsA(isA<PlaybackSourceUnavailable>()),
    );
  });

  test(
    'joins relative url and adds bearer token for the same origin',
    () async {
      gateway.streamInfo = StreamInfo(
        url: '/api/v1/stream/movie/7',
        storageId: 1,
        filePath: '/movies/a.mkv',
      );
      final adapter = _HeadAdapter();
      final resolved = await resolver(adapter).resolve(movie);

      expect(
        resolved.source.url,
        'http://media.local:8080/api/v1/stream/movie/7',
      );
      expect(resolved.source.httpHeaders, {
        'User-Agent': DownloadService.aria2UserAgent,
        'Authorization': 'Bearer token',
      });
      expect(resolved.filePath, '/movies/a.mkv');
      expect(adapter.requests.single.method, 'HEAD');
    },
  );

  test('follows redirect and drops credentials for another origin', () async {
    gateway.streamInfo = StreamInfo(url: '/api/v1/stream/movie/7');
    final adapter = _HeadAdapter(
      location: 'https://cdn.example.com/a.mkv?sig=1',
    );
    final resolved = await resolver(adapter).resolve(movie);

    expect(resolved.source.url, 'https://cdn.example.com/a.mkv?sig=1');
    expect(resolved.source.httpHeaders, {
      'User-Agent': DownloadService.aria2UserAgent,
    });
    expect(adapter.requests.single.headers['Authorization'], 'Bearer token');
  });

  test('uses basic auth for webdav storage on the same origin', () async {
    gateway.streamInfo = StreamInfo(
      url: 'http://dav.local/files/a.mkv',
      storageId: 3,
    );
    gateway.storage = Storage.fromJson({
      'id': 3,
      'name': 'dav',
      'type': 'webdav',
      'settings': {'url': 'http://dav.local', 'username': 'u', 'password': 'p'},
    });
    final resolved = await resolver(_HeadAdapter()).resolve(movie);

    expect(
      resolved.source.httpHeaders['Authorization'],
      HttpUtils.basicAuthHeader('u', 'p'),
    );
  });
}
