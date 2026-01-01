import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/download_task.dart';
import '../data/models/episode.dart';
import '../data/models/movie.dart';
import '../data/services/aria2_service.dart';
import '../data/services/download_service.dart';
import 'aria2_provider.dart';
import 'download_settings_provider.dart';
import 'server_provider.dart';

class DownloadManagerState {
  final List<DownloadTask> tasks;
  final bool isLoading;

  const DownloadManagerState({
    this.tasks = const [],
    this.isLoading = false,
  });

  DownloadManagerState copyWith({
    List<DownloadTask>? tasks,
    bool? isLoading,
  }) {
    return DownloadManagerState(
      tasks: tasks ?? this.tasks,
      isLoading: isLoading ?? this.isLoading,
    );
  }

  List<DownloadTask> get downloadingTasks =>
      tasks.where((t) => t.status == DownloadStatus.downloading || t.status == DownloadStatus.pending || t.status == DownloadStatus.paused).toList();

  List<DownloadTask> get completedTasks =>
      tasks.where((t) => t.status == DownloadStatus.completed).toList();

  List<DownloadTask> get failedTasks =>
      tasks.where((t) => t.status == DownloadStatus.failed).toList();

  bool isEpisodeDownloaded(int episodeId) =>
      tasks.any((t) => t.episodeId == episodeId && t.status == DownloadStatus.completed);

  bool isEpisodeDownloading(int episodeId) =>
      tasks.any((t) => t.episodeId == episodeId &&
          (t.status == DownloadStatus.downloading ||
           t.status == DownloadStatus.pending ||
           t.status == DownloadStatus.paused));

  DownloadTask? getTaskByEpisodeId(int episodeId) {
    try {
      return tasks.firstWhere((t) => t.episodeId == episodeId);
    } catch (_) {
      return null;
    }
  }

  bool isMovieDownloaded(int movieId) =>
      tasks.any((t) => t.movieId == movieId && t.status == DownloadStatus.completed);

  bool isMovieDownloading(int movieId) =>
      tasks.any((t) => t.movieId == movieId &&
          (t.status == DownloadStatus.downloading ||
           t.status == DownloadStatus.pending ||
           t.status == DownloadStatus.paused));

  DownloadTask? getTaskByMovieId(int movieId) {
    try {
      return tasks.firstWhere((t) => t.movieId == movieId);
    } catch (_) {
      return null;
    }
  }
}

class DownloadManagerNotifier extends StateNotifier<DownloadManagerState> {
  final DownloadService _service;
  final Aria2Service? _aria2;
  DateTime? _lastSaveTime;
  static const _saveThrottleMs = 2000;

  DownloadManagerNotifier(this._service, this._aria2) : super(const DownloadManagerState()) {
    _loadTasks();
  }

  Future<void> _loadTasks() async {
    state = state.copyWith(isLoading: true);
    final tasks = await _service.loadTasks();
    state = state.copyWith(tasks: tasks, isLoading: false);
  }

  Future<void> _saveTasks() async {
    await _service.saveTasks(state.tasks);
  }

  void _updateTask(DownloadTask task, {bool forceSave = false}) {
    final tasks = state.tasks.map((t) => t.id == task.id ? task : t).toList();
    state = state.copyWith(tasks: tasks);

    final now = DateTime.now();
    if (forceSave || _lastSaveTime == null ||
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
    if (state.tasks.any((t) => t.episodeId == episode.id)) {
      debugPrint('Episode ${episode.id} already in download list');
      return;
    }

    final task = await _service.createTask(
      episode: episode,
      tvShowName: tvShowName,
      seasonNumber: seasonNumber,
      storageName: storageName,
    );

    state = state.copyWith(tasks: [...state.tasks, task]);
    await _saveTasks();

    _startDownload(task);
  }

  Future<void> addDownloads({
    required List<Episode> episodes,
    required String tvShowName,
    required int seasonNumber,
    String? storageName,
  }) async {
    final newTasks = <DownloadTask>[];

    for (final episode in episodes) {
      if (state.tasks.any((t) => t.episodeId == episode.id)) {
        continue;
      }
      if (!episode.hasFile) continue;

      final task = await _service.createTask(
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

    for (final task in newTasks) {
      _startDownload(task);
    }
  }

  Future<void> addMovieDownload({required Movie movie}) async {
    if (state.tasks.any((t) => t.movieId == movie.id)) {
      debugPrint('Movie ${movie.id} already in download list');
      return;
    }

    final task = await _service.createMovieTask(movie: movie);

    state = state.copyWith(tasks: [...state.tasks, task]);
    await _saveTasks();

    _startDownload(task);
  }

  void _startDownload(DownloadTask task) {
    if (_aria2 != null) {
      _startAria2Download(task);
    } else {
      _startDioDownload(task);
    }
  }

  Future<void> _startAria2Download(DownloadTask task) async {
    try {
      // 使用 aria2 的 User-Agent 获取下载链接，这样 aria2 下载时用同样的 UA 就不会 403
      final info = await _service.getDownloadInfo(
        task,
        userAgent: DownloadService.aria2UserAgent,
      );
      if (info.url == null) {
        final updatedTask = task.copyWith(
          status: DownloadStatus.failed,
          errorMessage: info.error ?? '无法获取下载地址',
        );
        _updateTask(updatedTask, forceSave: true);
        _processNextInQueue();
        return;
      }

      final file = task.localPath;
      final dir = file.substring(0, file.lastIndexOf('/'));
      final filename = file.substring(file.lastIndexOf('/') + 1);

      debugPrint('[Aria2] Adding download: ${info.url}');
      debugPrint('[Aria2] Dir: $dir, Filename: $filename');
      debugPrint('[Aria2] Headers: ${info.headers}');

      final gid = await _aria2!.addUri(
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
      _updateTask(updatedTask, forceSave: true);

      _pollAria2Status(gid, updatedTask);
    } catch (e) {
      debugPrint('[Aria2] Error: $e');
      final updatedTask = task.copyWith(
        status: DownloadStatus.failed,
        errorMessage: 'aria2 错误: $e',
      );
      _updateTask(updatedTask, forceSave: true);
      _processNextInQueue();
    }
  }

  Future<void> _pollAria2Status(String gid, DownloadTask task) async {
    if (_aria2 == null) return;

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

        final status = await _aria2.tellStatus(gid);
        final downloadedBytes = int.tryParse(status['completedLength']?.toString() ?? '0') ?? 0;
        final totalBytes = int.tryParse(status['totalLength']?.toString() ?? '0') ?? 0;
        final downloadSpeed = double.tryParse(status['downloadSpeed']?.toString() ?? '0') ?? 0;
        final aria2Status = status['status'] as String?;

        debugPrint('[Aria2] Status: $aria2Status, Progress: $downloadedBytes/$totalBytes, Speed: ${(downloadSpeed / 1024 / 1024).toStringAsFixed(2)} MB/s');

        if (aria2Status == 'complete') {
          final updatedTask = currentTask.copyWith(
            status: DownloadStatus.completed,
            progress: 1.0,
            downloadedBytes: totalBytes,
            fileSize: totalBytes,
            completedAt: DateTime.now(),
          );
          _updateTask(updatedTask, forceSave: true);
          _processNextInQueue();
          break;
        } else if (aria2Status == 'error' || aria2Status == 'removed') {
          final errorMessage = status['errorMessage'] as String? ?? 'aria2 下载失败';
          final updatedTask = currentTask.copyWith(
            status: DownloadStatus.failed,
            errorMessage: errorMessage,
          );
          _updateTask(updatedTask, forceSave: true);
          _processNextInQueue();
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
      debugPrint('[Aria2] Poll error: $e');
    }
  }

  void _startDioDownload(DownloadTask task) {
    _service.startDownload(
      task,
      (updated) => _updateTask(updated),
      (completed) {
        _updateTask(completed, forceSave: true);
        _processNextInQueue();
      },
      (failed, error) {
        final updatedTask = failed.copyWith(
          status: DownloadStatus.failed,
          errorMessage: error,
        );
        _updateTask(updatedTask, forceSave: true);
        _processNextInQueue();
      },
    );
  }

  void _processNextInQueue() {
    final pendingTasks = state.tasks.where((t) => t.status == DownloadStatus.pending).toList();
    final downloadingCount = state.tasks.where((t) => t.status == DownloadStatus.downloading).length;

    if (downloadingCount < 2 && pendingTasks.isNotEmpty) {
      _startDownload(pendingTasks.first);
    }
  }

  void pauseDownload(String taskId) {
    _service.pauseDownload(taskId);
    final task = state.tasks.firstWhere((t) => t.id == taskId);
    _updateTask(task.copyWith(status: DownloadStatus.paused), forceSave: true);
  }

  void resumeDownload(String taskId) {
    final task = state.tasks.firstWhere((t) => t.id == taskId);
    final updatedTask = task.copyWith(status: DownloadStatus.pending);
    _updateTask(updatedTask, forceSave: true);
    _startDownload(updatedTask);
  }

  Future<void> deleteDownload(String taskId) async {
    final task = state.tasks.firstWhere((t) => t.id == taskId);
    await _service.deleteDownload(task);
    state = state.copyWith(tasks: state.tasks.where((t) => t.id != taskId).toList());
    await _saveTasks();
  }

  Future<void> retryDownload(String taskId) async {
    final task = state.tasks.firstWhere((t) => t.id == taskId);
    final updatedTask = task.copyWith(
      status: DownloadStatus.pending,
      progress: 0,
      downloadedBytes: 0,
      errorMessage: null,
    );
    _updateTask(updatedTask, forceSave: true);
    _startDownload(updatedTask);
  }

  Future<void> deleteAllCompleted() async {
    final completed = state.completedTasks;
    for (final task in completed) {
      await _service.deleteDownload(task);
    }
    state = state.copyWith(
      tasks: state.tasks.where((t) => t.status != DownloadStatus.completed).toList(),
    );
    await _saveTasks();
  }
}

final downloadServiceProvider = Provider<DownloadService?>((ref) {
  final serverUrl = ref.watch(serverUrlProvider);
  if (serverUrl == null || serverUrl.isEmpty) return null;

  final downloadSettings = ref.watch(downloadSettingsProvider);

  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(hours: 2),
  ));

  final service = DownloadService(dio, serverUrl);
  service.useMultiThread = downloadSettings.multiThreadEnabled;
  service.threadCount = downloadSettings.threadCount;
  return service;
});

final downloadManagerProvider =
    StateNotifierProvider<DownloadManagerNotifier, DownloadManagerState>((ref) {
  final service = ref.watch(downloadServiceProvider);
  final aria2 = ref.watch(aria2ServiceProvider);
  if (service == null) {
    return DownloadManagerNotifier(DownloadService(Dio(), ''), null);
  }
  return DownloadManagerNotifier(service, aria2);
});
