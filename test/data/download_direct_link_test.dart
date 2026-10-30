import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/data/models/download_task.dart';
import 'package:media_player/data/services/download_service.dart';

class _RouteAdapter implements HttpClientAdapter {
  _RouteAdapter(this.routes);

  final Map<String, Object> routes;
  final List<Uri> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options.uri);
    final body = routes[options.uri.path];
    if (body == null) return ResponseBody.fromString('', 404);
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  final task = DownloadTask(
    id: 'm1',
    type: DownloadType.movie,
    movieId: 1,
    downloadUrl: '',
    localPath: '/tmp/a.mkv',
    status: DownloadStatus.pending,
    createdAt: DateTime(2026),
  );

  DownloadService service(_RouteAdapter adapter) => DownloadService(
    Dio()..httpClientAdapter = adapter,
    'http://server',
    tokenGetter: () => 'token',
  );

  Map<String, Object> routes(Map<String, Object> download) => {
    '/api/v1/download/movie/1/url': {'data': download},
    '/api/v1/movies/1/stream': {
      'data': {'storage_id': 5, 'file_path': '/电影/a.mkv'},
    },
    '/api/v1/storages': {'data': <Object>[]},
  };

  test('a direct link carries only its own headers and connections', () async {
    final adapter = _RouteAdapter(
      routes({
        'delivery': 'direct_link',
        'kind': 'file',
        'url': 'https://cdn.example/a?auth_key=1',
        'headers': {'Cookie': '__puus=x'},
        'max_connections': 16,
      }),
    );
    final info = await service(adapter).getDownloadInfo(task, userAgent: 'UA');

    expect(info.url, 'https://cdn.example/a?auth_key=1');
    expect(info.headers, {'User-Agent': 'UA', 'Cookie': '__puus=x'});
    expect(info.maxConnections, 16);
    expect(adapter.requests.first.queryParameters, {
      'direct': '1',
      'user_agent': 'UA',
    });
  });

  test('link headers override the default user agent', () async {
    const desktop = 'quark-cloud-drive/2.5.56';
    final adapter = _RouteAdapter(
      routes({
        'delivery': 'direct_link',
        'url': 'https://cdn.example/a',
        'headers': {
          'Cookie': '__pus=a; __puus=x',
          'User-Agent': desktop,
          'Referer': 'https://pan.quark.cn/',
        },
        'max_connections': 512,
      }),
    );
    final info = await service(adapter).getDownloadInfo(task, userAgent: 'UA');

    expect(info.headers, {
      'User-Agent': desktop,
      'Cookie': '__pus=a; __puus=x',
      'Referer': 'https://pan.quark.cn/',
    });
    expect(info.maxConnections, 512);
  });

  test('connections share the global budget across concurrent tasks', () {
    expect(DownloadService.shareConnections(512, 1), 256);
    expect(DownloadService.shareConnections(512, 2), 128);
    expect(DownloadService.shareConnections(16, 2), 16);
    expect(DownloadService.shareConnections(512, 0), 256);
    expect(DownloadService.shareConnections(null, 1), isNull);
  });

  test('an old server response keeps the server url and auth', () async {
    final adapter = _RouteAdapter(routes({'url': '/api/v1/stream/5/a.mkv'}));
    final info = await service(adapter).getDownloadInfo(task);

    expect(info.url, 'http://server/api/v1/stream/5/a.mkv');
    expect(info.headers, {'Authorization': 'Bearer token'});
    expect(info.maxConnections, isNull);
  });
}
