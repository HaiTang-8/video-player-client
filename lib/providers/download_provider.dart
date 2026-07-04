import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/utils/download_queue.dart';
import '../core/utils/http_utils.dart';
import '../data/models/download_task.dart';
import '../data/models/episode.dart';
import '../data/models/movie.dart';
import '../data/services/api_client.dart';
import '../data/services/aria2_service.dart';
import '../data/services/download_service.dart';
import '../data/services/log_service.dart';
import '../data/services/proxy_http_client_adapter.dart';
import 'aria2_provider.dart';
import 'download_settings_provider.dart';
import 'auth_provider.dart';
import 'server_provider.dart';

class DownloadManagerState {
  final List<DownloadTask> tasks;
  final bool isLoading;

  const DownloadManagerState({this.tasks = const [], this.isLoading = false});

  DownloadManagerState copyWith({List<DownloadTask>? tasks, bool? isLoading}) {
    return DownloadManagerState(
      tasks: tasks ?? this.tasks,
      isLoading: isLoading ?? this.isLoading,
    );
  }

  List<DownloadTask> get downloadingTasks =>
      tasks
          .where(
            (t) =>
                t.status == DownloadStatus.downloading ||
                t.status == DownloadStatus.pending ||
                t.status == DownloadStatus.paused,
          )
          .toList();

  List<DownloadTask> get completedTasks =>
      tasks.where((t) => t.status == DownloadStatus.completed).toList();

  List<DownloadTask> get failedTasks =>
      tasks.where((t) => t.status == DownloadStatus.failed).toList();

  bool isEpisodeDownloaded(int episodeId) => tasks.any(
    (t) => t.episodeId == episodeId && t.status == DownloadStatus.completed,
  );

  bool isEpisodeDownloading(int episodeId) => tasks.any(
    (t) =>
        t.episodeId == episodeId &&
        (t.status == DownloadStatus.downloading ||
            t.status == DownloadStatus.pending ||
            t.status == DownloadStatus.paused),
  );

  DownloadTask? getTaskByEpisodeId(int episodeId) {
    try {
      return tasks.firstWhere((t) => t.episodeId == episodeId);
    } catch (_) {
      return null;
    }
  }

  bool isMovieDownloaded(int movieId) => tasks.any(
    (t) => t.movieId == movieId && t.status == DownloadStatus.completed,
  );

  bool isMovieDownloading(int movieId) => tasks.any(
    (t) =>
        t.movieId == movieId &&
        (t.status == DownloadStatus.downloading ||
            t.status == DownloadStatus.pending ||
            t.status == DownloadStatus.paused),
  );

  DownloadTask? getTaskByMovieId(int movieId) {
    try {
      return tasks.firstWhere((t) => t.movieId == movieId);
    } catch (_) {
      return null;
    }
  }
}

final downloadServiceProvider = Provider<DownloadService?>((ref) {
  final server = ref.watch(serverListProvider).currentServer;
  if (server == null || server.url.isEmpty) return null;

  final downloadSettings = ref.watch(downloadSettingsProvider);

  final serverUri = Uri.tryParse(server.url);
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(hours: 2),
    ),
  );
  configureDioProxy(dio, server.proxyUrl);
  configureDioAuthRetry(dio);
  dio.interceptors.add(
    AuthInterceptor(
      tokenGetter: () => ref.read(authProvider).tokens?.accessToken,
      onTokenExpired: () => ref.read(authProvider.notifier).refreshToken(),
      shouldAttachToken:
          (options) =>
              serverUri == null
                  ? true
                  : HttpUtils.sameOrigin(serverUri, options.uri),
      shouldRefreshOn401:
          (options) =>
              serverUri == null
                  ? true
                  : HttpUtils.sameOrigin(serverUri, options.uri),
    ),
  );

  final service = DownloadService(
    dio,
    server.url,
    tokenGetter: () => ref.read(authProvider).tokens?.accessToken,
  );
  service.useMultiThread = downloadSettings.multiThreadEnabled;
  service.threadCount = downloadSettings.threadCount;
  return service;
});

final downloadManagerProvider =
    NotifierProvider<DownloadManagerNotifier, DownloadManagerState>(
      DownloadManagerNotifier.new,
    );

class DownloadManagerNotifier extends Notifier<DownloadManagerState> {
  DateTime? _lastSaveTime;
  static const _saveThrottleMs = 2000;
  static const int _maxConcurrentDownloads = 2;
  final Set<String> _startingTaskIds = <String>{};

  @override
  DownloadManagerState build() {
    Future.microtask(_loadTasks);
    return const DownloadManagerState();
  }

  DownloadService? get _service => ref.read(downloadServiceProvider);
  Aria2Service? get _aria2 => ref.read(aria2ServiceProvider);

  Future<void> _loadTasks() async {
    final service = _service;
    if (service == null) return;
    _startingTaskIds.clear();
    state = state.copyWith(isLoading: true);
    final tasks = await service.loadTasks();
    state = state.copyWith(tasks: tasks, isLoading: false);
  }

  Future<void> reloadTasks() => _loadTasks();

  void clearTasksInMemory() {
    _startingTaskIds.clear();
    state = state.copyWith(tasks: []);
  }

  Future<void> _saveTasks() async {
    final service = _service;
    if (service == null) return;
    await service.saveTasks(state.tasks);
  }

  void _updateTask(DownloadTask task, {bool forceSave = false}) {
    final tasks = state.tasks.map((t) => t.id == task.id ? task : t).toList();
    state = state.copyWith(tasks: tasks);

    final now = DateTime.now();
    if (forceSave ||
        _lastSaveTime == null ||
        now.difference(_lastSaveTime!).inMilliseconds >= _saveThrottleMs) {
      _lastSaveTime = now;
      _saveTasks();
    }
  }

  Future<void> addDownload({
    required Episode episode,
    required String tvShowName,
    required int seasonNumber,
    String? storageName,
  }) async {
    final service = _service;
    if (service == null) return;
    if (state.tasks.any((t) => t.episodeId == episode.id)) {
      LogService.instance.debug(
        'Download',
        'Episode ${episode.id} already in download list',
      );
      return;
    }

    final task = await service.createTask(
      episode: episode,
      tvShowName: tvShowName,
      seasonNumber: seasonNumber,
      storageName: storageName,
    );

    state = state.copyWith(tasks: [...state.tasks, task]);
    await _saveTasks();

    _processQueue();
  }

  Future<void> addDownloads({
    required List<Episode> episodes,
    required String tvShowName,
    required int seasonNumber,
    String? storageName,
  }) async {
    final service = _service;
    if (service == null) return;
    final newTasks = <DownloadTask>[];

    for (final episode in episodes) {
      if (state.tasks.any((t) => t.episodeId == episode.id)) continue;
      if (!episode.hasFile) continue;

      final task = await service.createTask(
        episode: episode,
        tvShowName: tvShowName,
        seasonNumber: seasonNumber,
        storageName: storageName,
      );
      newTasks.add(task);
    }

    if (newTasks.isEmpty) return;

    state = state.copyWith(tasks: [...state.tasks, ...newTasks]);
    await _saveTasks();

    _processQueue();
  }

  Future<void> addMovieDownload({required Movie movie}) async {
    final service = _service;
    if (service == null) return;
    if (state.tasks.any((t) => t.movieId == movie.id)) {
      LogService.instance.debug(
        'Download',
        'Movie ${movie.id} already in download list',
      );
      return;
    }

    final task = await service.createMovieTask(movie: movie);

    state = state.copyWith(tasks: [...state.tasks, task]);
    await _saveTasks();

    _processQueue();
  }

  void _startDownload(DownloadTask task) {
    if (_aria2 != null) {
      _startAria2Download(task);
    } else {
      _startDioDownload(task);
    }
  }

  Future<void> _startAria2Download(DownloadTask task) async {
    final service = _service;
    final aria2 = _aria2;
    if (service == null || aria2 == null) {
      // Cannot start right now; keep task pending so it can be retried later.
      _startingTaskIds.remove(task.id);
      _updateTask(
        task.copyWith(status: DownloadStatus.pending),
        forceSave: true,
      );
      return;
    }

    try {
      final info = await service.getDownloadInfo(
        task,
        userAgent: DownloadService.aria2UserAgent,
      );
      if (info.url == null) {
        _startingTaskIds.remove(task.id);
        final updatedTask = task.copyWith(
          status: DownloadStatus.failed,
          errorMessage: info.error ?? '无法获取下载地址',
        );
        _updateTask(updatedTask, forceSave: true);
        _processQueue();
        return;
      }

      final file = task.localPath;
      final dir = file.substring(0, file.lastIndexOf('/'));
      final filename = file.substring(file.lastIndexOf('/') + 1);

      if (kDebugMode) {
        LogService.instance.debug(
          'Aria2',
          'Adding download taskId=${task.id}, dir=$dir, filename=$filename, headerKeys=${info.headers.keys.toList()}',
        );
      }

      final gid = await aria2.addUri(
        info.url!,
        dir: dir,
        filename: filename,
        headers: info.headers,
      );

      var updatedTask = task.copyWith(
        status: DownloadStatus.downloading,
        downloadUrl: info.url,
        aria2Gid: gid,
      );
      _startingTaskIds.remove(task.id);
      _updateTask(updatedTask, forceSave: true);

      _pollAria2Status(gid, updatedTask);
    } catch (e) {
      LogService.instance.error('Aria2', 'Error: $e');
      _startingTaskIds.remove(task.id);
      final updatedTask = task.copyWith(
        status: DownloadStatus.failed,
        errorMessage: 'aria2 错误: $e',
      );
      _updateTask(updatedTask, forceSave: true);
      _processQueue();
    }
  }

  Future<void> _pollAria2Status(String gid, DownloadTask task) async {
    final aria2 = _aria2;
    if (aria2 == null) return;

    try {
      while (true) {
        await Future.delayed(const Duration(seconds: 1));

        final currentTask = state.tasks.firstWhere(
          (t) => t.id == task.id,
          orElse: () => task,
        );
        if (currentTask.status == DownloadStatus.paused ||
            currentTask.status == DownloadStatus.completed ||
            currentTask.status == DownloadStatus.failed) {
          break;
        }

        final status = await aria2.tellStatus(gid);
        final downloadedBytes =
            int.tryParse(status['completedLength']?.toString() ?? '0') ?? 0;
        final totalBytes =
            int.tryParse(status['totalLength']?.toString() ?? '0') ?? 0;
        final downloadSpeed =
            double.tryParse(status['downloadSpeed']?.toString() ?? '0') ?? 0;
        final aria2Status = status['status'] as String?;

        LogService.instance.debug(
          'Aria2',
          'Status: $aria2Status, Progress: $downloadedBytes/$totalBytes, Speed: ${(downloadSpeed / 1024 / 1024).toStringAsFixed(2)} MB/s',
        );

        if (aria2Status == 'complete') {
          final updatedTask = currentTask.copyWith(
            status: DownloadStatus.completed,
            progress: 1.0,
            downloadedBytes: totalBytes,
            fileSize: totalBytes,
            completedAt: DateTime.now(),
          );
          _updateTask(updatedTask, forceSave: true);
          _processQueue();
          break;
        } else if (aria2Status == 'error' || aria2Status == 'removed') {
          final errorMessage =
              status['errorMessage'] as String? ?? 'aria2 下载失败';
          final updatedTask = currentTask.copyWith(
            status: DownloadStatus.failed,
            errorMessage: errorMessage,
          );
          _updateTask(updatedTask, forceSave: true);
          _processQueue();
          break;
        } else if (aria2Status == 'active' || aria2Status == 'waiting') {
          final progress = totalBytes > 0 ? downloadedBytes / totalBytes : 0.0;
          final updatedTask = currentTask.copyWith(
            status: DownloadStatus.downloading,
            progress: progress,
            downloadedBytes: downloadedBytes,
            fileSize: totalBytes > 0 ? totalBytes : currentTask.fileSize,
            downloadSpeed: downloadSpeed,
          );
          _updateTask(updatedTask);
        } else if (aria2Status == 'paused') {
          break;
        }
      }
    } catch (e) {
      LogService.instance.error('Aria2', 'Poll error: $e');
    }
  }

  void _startDioDownload(DownloadTask task) {
    final service = _service;
    if (service == null) {
      // Cannot start right now; keep task pending so it can be retried later.
      _startingTaskIds.remove(task.id);
      _updateTask(
        task.copyWith(status: DownloadStatus.pending),
        forceSave: true,
      );
      return;
    }
    try {
      service
          .startDownload(
            task,
            (updated) {
              _startingTaskIds.remove(updated.id);
              _updateTask(updated);
            },
            (completed) {
              _startingTaskIds.remove(completed.id);
              _updateTask(completed, forceSave: true);
              _processQueue();
            },
            (failed, error) {
              _startingTaskIds.remove(failed.id);
              final updatedTask = failed.copyWith(
                status: DownloadStatus.failed,
                errorMessage: error,
              );
              _updateTask(updatedTask, forceSave: true);
              _processQueue();
            },
          )
          .catchError((e, _) {
            _startingTaskIds.remove(task.id);
            final current = state.tasks.firstWhere(
              (t) => t.id == task.id,
              orElse: () => task,
            );
            // If no callback updated the state, mark as failed to avoid "starting" forever.
            if (current.status == DownloadStatus.pending ||
                current.status == DownloadStatus.downloading) {
              _updateTask(
                current.copyWith(
                  status: DownloadStatus.failed,
                  errorMessage: e.toString(),
                ),
                forceSave: true,
              );
              _processQueue();
            }
          });
    } catch (e) {
      _startingTaskIds.remove(task.id);
      final current = state.tasks.firstWhere(
        (t) => t.id == task.id,
        orElse: () => task,
      );
      _updateTask(
        current.copyWith(
          status: DownloadStatus.failed,
          errorMessage: e.toString(),
        ),
        forceSave: true,
      );
      _processQueue();
    }
  }

  void _processQueue() {
    // If we can't start downloads (e.g. server not configured), do not change task states.
    if (_service == null) return;

    // Fill available slots up to the concurrency limit.
    final tasksForPicking = state.tasks
        .map(
          (t) =>
              _startingTaskIds.contains(t.id)
                  ? t.copyWith(status: DownloadStatus.downloading)
                  : t,
        )
        .toList(growable: false);
    final toStart = pickPendingTasksToStart(
      tasksForPicking,
      maxConcurrent: _maxConcurrentDownloads,
    );
    if (toStart.isEmpty) return;

    for (final task in toStart) {
      if (_startingTaskIds.contains(task.id)) continue;
      final original = state.tasks.firstWhere(
        (t) => t.id == task.id,
        orElse: () => task,
      );
      _startingTaskIds.add(task.id);
      try {
        _startDownload(original);
      } catch (e) {
        _startingTaskIds.remove(task.id);
        _updateTask(
          original.copyWith(
            status: DownloadStatus.failed,
            errorMessage: e.toString(),
          ),
          forceSave: true,
        );
        _processQueue();
      }
    }
  }

  void pauseDownload(String taskId) {
    final service = _service;
    if (service == null) return;
    _startingTaskIds.remove(taskId);
    service.pauseDownload(taskId);
    final task = state.tasks.firstWhere((t) => t.id == taskId);
    _updateTask(task.copyWith(status: DownloadStatus.paused), forceSave: true);
    _processQueue();
  }

  Future<void> pauseAllDownloads() async {
    final service = _service;
    if (service == null) return;
    final activeTasks =
        state.tasks
            .where(
              (t) =>
                  t.status == DownloadStatus.downloading ||
                  t.status == DownloadStatus.pending,
            )
            .toList();
    if (activeTasks.isNotEmpty) {
      final updatedTasks =
          state.tasks.map((t) {
            if (t.status == DownloadStatus.downloading ||
                t.status == DownloadStatus.pending) {
              return t.copyWith(status: DownloadStatus.paused);
            }
            return t;
          }).toList();
      state = state.copyWith(tasks: updatedTasks);
      await _saveTasks();
    }
    service.pauseAllAndCleanup(activeTasks);
    _startingTaskIds.clear();
    state = state.copyWith(tasks: []);
  }

  void resumeDownload(String taskId) {
    final service = _service;
    if (service == null) return;
    final task = state.tasks.firstWhere((t) => t.id == taskId);
    final updatedTask = task.copyWith(status: DownloadStatus.downloading);
    _updateTask(updatedTask, forceSave: true);
    service.resumeDownload(taskId);
  }

  Future<void> deleteDownload(String taskId) async {
    final service = _service;
    if (service == null) return;
    _startingTaskIds.remove(taskId);
    final task = state.tasks.firstWhere((t) => t.id == taskId);
    await service.deleteDownload(task);
    state = state.copyWith(
      tasks: state.tasks.where((t) => t.id != taskId).toList(),
    );
    await _saveTasks();
  }

  Future<void> retryDownload(String taskId) async {
    _startingTaskIds.remove(taskId);
    final task = state.tasks.firstWhere((t) => t.id == taskId);
    final updatedTask = task.copyWith(
      status: DownloadStatus.pending,
      progress: 0,
      downloadedBytes: 0,
      errorMessage: null,
    );
    _updateTask(updatedTask, forceSave: true);
    _processQueue();
  }

  Future<void> deleteAllCompleted() async {
    final service = _service;
    if (service == null) return;
    final completed = state.completedTasks;
    for (final task in completed) {
      await service.deleteDownload(task);
    }
    state = state.copyWith(
      tasks:
          state.tasks
              .where((t) => t.status != DownloadStatus.completed)
              .toList(),
    );
    await _saveTasks();
  }
}
