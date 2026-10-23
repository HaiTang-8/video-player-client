import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_constants.dart';
import '../../data/models/storage.dart';
import '../../data/models/stream_info.dart';
import '../../data/models/subtitle_info.dart';
import '../../data/services/media_service.dart';
import '../../providers/providers.dart';
import 'playback_gateways.dart';
import 'playback_item.dart';

/// 基于 Riverpod 的数据访问实现，由播放页创建
class RiverpodPlaybackGateway
    implements PlaybackSourceGateway, WatchProgressGateway, SubtitleDelayStore {
  RiverpodPlaybackGateway(this._ref)
    : _mediaService = _ref.read(mediaServiceProvider);

  final WidgetRef _ref;
  final MediaService? _mediaService;

  @override
  String? get serverUrl => _ref.read(serverUrlProvider);

  @override
  Duration read(PlaybackItem item) {
    final key = _subtitleDelayKey(item);
    final ms = key == null ? null : _prefs.getInt(key);
    return Duration(milliseconds: ms ?? 0);
  }

  @override
  Future<void> write(PlaybackItem item, Duration delay) async {
    final key = _subtitleDelayKey(item);
    if (key == null) return;
    if (delay == Duration.zero) {
      await _prefs.remove(key);
    } else {
      await _prefs.setInt(key, delay.inMilliseconds);
    }
  }

  SharedPreferences get _prefs => _ref.read(sharedPreferencesProvider);

  /// 没有当前服务器时不保存
  String? _subtitleDelayKey(PlaybackItem item) {
    final serverId = _ref.read(serverListProvider).currentServerId;
    if (serverId == null) return null;
    return AppConstants.subtitleDelayKey(serverId, switch (item) {
      MoviePlaybackItem(:final movieId) => 'movie_$movieId',
      EpisodePlaybackItem(:final tvShowId) => 'tv_$tvShowId',
    });
  }

  @override
  String? get accessToken => _ref.read(authProvider).tokens?.accessToken;

  @override
  Future<String?> findDownloadedFile(PlaybackItem item) async {
    var state = _ref.read(downloadManagerProvider);
    if (state.isLoading) state = await _waitForDownloadManagerReady();
    final task = switch (item) {
      MoviePlaybackItem(:final movieId) =>
        state.isMovieDownloaded(movieId)
            ? state.getTaskByMovieId(movieId)
            : null,
      EpisodePlaybackItem(:final episodeId) =>
        state.isEpisodeDownloaded(episodeId)
            ? state.getTaskByEpisodeId(episodeId)
            : null,
    };
    if (task != null && await File(task.localPath).exists()) {
      return task.localPath;
    }
    return null;
  }

  @override
  Future<StreamInfo?> fetchStreamInfo(PlaybackItem item) {
    switch (item) {
      case MoviePlaybackItem(:final movieId):
        return _ref.read(movieStreamProvider(movieId).future);
      case EpisodePlaybackItem():
        final key = (
          tvShowId: item.tvShowId,
          seasonId: item.seasonId,
          episodeId: item.episodeId,
        );
        _ref.invalidate(episodeStreamProvider(key));
        return _ref.read(episodeStreamProvider(key).future);
    }
  }

  @override
  Future<Storage?> findStorage(int storageId) async {
    final current = _ref.read(storagesProvider).value;
    if (current != null) {
      final found = current.where((s) => s.id == storageId).firstOrNull;
      if (found != null) return found;
    }

    await _ref.read(storagesProvider.notifier).loadStorages();
    final loaded = _ref.read(storagesProvider).value;
    if (loaded == null) return null;
    return loaded.where((s) => s.id == storageId).firstOrNull;
  }

  @override
  Future<List<SubtitleInfo>> listSubtitles({
    required int storageId,
    required String filePath,
  }) async {
    final service = _mediaService;
    if (service == null) return const [];
    final response = await service.getSubtitles(
      storageId: storageId,
      filePath: filePath,
    );
    return response.data ?? const [];
  }

  @override
  bool get isAvailable => _mediaService != null;

  @override
  Future<void> upload(
    PlaybackItem item,
    Duration position,
    Duration duration,
  ) async {
    final service = _mediaService;
    if (service == null) return;
    switch (item) {
      case MoviePlaybackItem(:final movieId):
        await service.updateWatchProgress(
          mediaType: 'movie',
          mediaId: movieId,
          position: position.inSeconds,
          duration: duration.inSeconds,
        );
      case EpisodePlaybackItem(:final tvShowId, :final episodeId):
        await service.updateWatchProgress(
          mediaType: 'tv',
          mediaId: tvShowId,
          episodeId: episodeId,
          position: position.inSeconds,
          duration: duration.inSeconds,
        );
    }
  }

  @override
  void publish(PlaybackItem item, Duration position, Duration duration) {
    final notifier = _ref.read(watchProgressProvider.notifier);
    switch (item) {
      case MoviePlaybackItem(:final movieId):
        notifier.upsertFromPlayback(
          mediaType: 'movie',
          mediaId: movieId,
          position: position.inSeconds,
          duration: duration.inSeconds,
        );
      case EpisodePlaybackItem(
        :final tvShowId,
        :final seasonId,
        :final episodeId,
      ):
        notifier.upsertFromPlayback(
          mediaType: 'tv',
          mediaId: tvShowId,
          episodeId: episodeId,
          seasonId: seasonId,
          position: position.inSeconds,
          duration: duration.inSeconds,
        );
    }
  }

  /// 等待下载管理器加载完成，最多等待 5 秒
  Future<DownloadManagerState> _waitForDownloadManagerReady() async {
    final completer = Completer<DownloadManagerState>();
    final subscription = _ref.listenManual<DownloadManagerState>(
      downloadManagerProvider,
      (previous, next) {
        if (!next.isLoading && !completer.isCompleted) {
          completer.complete(next);
        }
      },
      fireImmediately: true,
    );
    final timer = Timer(const Duration(seconds: 5), () {
      if (!completer.isCompleted) {
        completer.complete(_ref.read(downloadManagerProvider));
      }
    });
    try {
      return await completer.future;
    } finally {
      timer.cancel();
      subscription.close();
    }
  }
}
