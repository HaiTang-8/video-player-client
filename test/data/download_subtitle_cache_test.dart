import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/data/models/download_task.dart';
import 'package:media_player/data/services/download_service.dart';

/// 按路径返回固定响应
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
    final isText = body is String;
    return ResponseBody.fromString(
      isText ? body : jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: [
          isText ? 'text/plain; charset=utf-8' : 'application/json',
        ],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late Directory dir;
  late DownloadTask task;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('subtitle_cache');
    final video = File('${dir.path}/Show.S01E02.mkv')..writeAsStringSync('v');
    task = DownloadTask(
      id: 't1',
      type: DownloadType.episode,
      tvShowId: 1,
      seasonId: 2,
      episodeId: 3,
      downloadUrl: '',
      localPath: video.path,
      status: DownloadStatus.completed,
      createdAt: DateTime(2026),
    );
  });

  // deleteDownload 会顺带删除变空的目录
  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  DownloadService service(_RouteAdapter adapter) =>
      DownloadService(Dio()..httpClientAdapter = adapter, 'http://server');

  _RouteAdapter routes() => _RouteAdapter({
    '/api/v1/tvshows/1/seasons/2/episodes/3/stream': {
      'data': {'storage_id': 9, 'file_path': '/tv/Show.S01E02.mkv'},
    },
    '/api/v1/subtitles': {
      'data': [
        {
          'name': 'eng',
          'path': '/tv/a.eng.srt',
          'url': '/sub/eng',
          'score': 60,
        },
        {
          'name': 'chs',
          'path': '/tv/a.chs.ASS',
          'url': '/sub/chs',
          'language': 'chs',
          'score': 95,
        },
      ],
    },
    '/sub/chs': '[Script Info]\n中文',
    '/sub/eng': '1\n00:00:01,000 --> 00:00:02,000\nhi\n',
  });

  test('saves matched subtitles next to the video, best first', () async {
    final adapter = routes();
    final cached = await service(adapter).cacheSubtitles(task);

    expect(cached.map((s) => s.name), ['chs', 'eng']);
    expect(cached.first.localPath, '${dir.path}/Show.S01E02.1.chs.ass');
    expect(cached.last.localPath, '${dir.path}/Show.S01E02.2.srt');
    expect(
      File(cached.first.localPath!).readAsStringSync(),
      '[Script Info]\n中文',
    );
    final query =
        adapter.requests
            .firstWhere((u) => u.path == '/api/v1/subtitles')
            .queryParameters;
    expect(query, {'storage_id': '9', 'file_path': '/tv/Show.S01E02.mkv'});
  });

  test('skips when the video is not on this machine', () async {
    final adapter = routes();
    final remote = task.copyWith(localPath: '/nowhere/Show.S01E02.mkv');
    expect(await service(adapter).cacheSubtitles(remote), isEmpty);
    expect(adapter.requests, isEmpty);
  });

  test('task json keeps cached subtitles and deleting removes them', () async {
    final svc = service(routes());
    final cached = await svc.cacheSubtitles(task);
    final restored = DownloadTask.fromJson(
      jsonDecode(jsonEncode(task.copyWith(cachedSubtitles: cached).toJson()))
          as Map<String, dynamic>,
    );
    expect(restored.cachedSubtitles.map((s) => s.localPath), [
      for (final s in cached) s.localPath,
    ]);

    await svc.deleteDownload(restored);
    for (final s in cached) {
      expect(File(s.localPath!).existsSync(), isFalse);
    }
  });
}
