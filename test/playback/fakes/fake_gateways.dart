import 'dart:async';

import 'package:media_player/data/models/storage.dart';
import 'package:media_player/data/models/stream_info.dart';
import 'package:media_player/data/models/stream_link.dart';
import 'package:media_player/data/models/subtitle_info.dart';
import 'package:media_player/playback/session/playback_gateways.dart';
import 'package:media_player/playback/session/playback_item.dart';

class FakeSourceGateway implements PlaybackSourceGateway {
  @override
  String? serverUrl = 'http://media.local:8080';

  @override
  String? accessToken = 'token';

  String? downloadedFile;
  StreamInfo? streamInfo;
  Storage? storage;
  List<SubtitleInfo> subtitles = const [];
  List<SubtitleInfo> cached = const [];
  Object? streamInfoError;
  final List<PlaybackItem> streamRequests = [];

  /// 按版本返回直链；为空时返回 null
  StreamLink? Function(String? variant)? link;
  final List<({int? sourceId, String? variant, bool fresh})> linkRequests = [];

  @override
  Future<String?> findDownloadedFile(PlaybackItem item) async => downloadedFile;

  @override
  Future<StreamInfo?> fetchStreamInfo(PlaybackItem item) async {
    streamRequests.add(item);
    final error = streamInfoError;
    if (error != null) throw error;
    return streamInfo;
  }

  @override
  Future<StreamLink?> fetchLink(
    PlaybackItem item, {
    int? sourceId,
    String? variant,
    bool fresh = false,
  }) async {
    linkRequests.add((sourceId: sourceId, variant: variant, fresh: fresh));
    return link?.call(variant);
  }

  List<LinkVariant> variants = const [];
  Completer<void>? variantsGate;
  int variantRequests = 0;

  @override
  Future<List<LinkVariant>> fetchVariants(PlaybackItem item) async {
    variantRequests++;
    await variantsGate?.future;
    return variants;
  }

  @override
  Future<List<SubtitleInfo>> cachedSubtitles(PlaybackItem item) async => cached;

  @override
  Future<Storage?> findStorage(int storageId) async => storage;

  @override
  Future<List<SubtitleInfo>> listSubtitles({
    required int storageId,
    required String filePath,
  }) async => subtitles;
}

class FakeProgressGateway implements WatchProgressGateway {
  @override
  bool isAvailable = true;

  final List<String> uploads = [];
  final List<String> publishes = [];

  @override
  Future<void> upload(
    PlaybackItem item,
    Duration position,
    Duration duration,
  ) async => uploads.add('${position.inSeconds}/${duration.inSeconds}');

  @override
  void publish(PlaybackItem item, Duration position, Duration duration) =>
      publishes.add('${position.inSeconds}/${duration.inSeconds}');
}

SubtitleInfo subtitleInfo(String name, int score, {String? language}) =>
    SubtitleInfo(
      name: name,
      path: '/subs/$name',
      url: '/api/v1/subtitles/$name',
      language: language,
      score: score,
    );

/// 按与正式实现相同的范围保存：剧集按整部剧，电影按单部
class FakeSubtitleDelayStore implements SubtitleDelayStore {
  final Map<String, Duration> saved = {};

  static String key(PlaybackItem item) => switch (item) {
    MoviePlaybackItem(:final movieId) => 'movie_$movieId',
    EpisodePlaybackItem(:final tvShowId) => 'tv_$tvShowId',
  };

  @override
  Duration read(PlaybackItem item) => saved[key(item)] ?? Duration.zero;

  @override
  Future<void> write(PlaybackItem item, Duration delay) async {
    if (delay == Duration.zero) {
      saved.remove(key(item));
    } else {
      saved[key(item)] = delay;
    }
  }
}
