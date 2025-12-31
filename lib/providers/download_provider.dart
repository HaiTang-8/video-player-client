import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/download_task.dart';
import '../data/models/episode.dart';
import '../data/services/download_service.dart';
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
      tasks.where((t) => t.status == DownloadStatus.downloading || t.status == DownloadStatus.pending).toList();

  List<DownloadTask> get completedTasks =>
      tasks.where((t) => t.status == DownloadStatus.completed).toList();

  List<DownloadTask> get failedTasks =>
      tasks.where((t) => t.status == DownloadStatus.failed).toList();

  bool isEpisodeDownloaded(int episodeId) =>
      tasks.any((t) => t.episodeId == episodeId && t.status == DownloadStatus.completed);

  bool isEpisodeDownloading(int episodeId) =>
      tasks.any((t) => t.episodeId == episodeId && (t.status == DownloadStatus.downloading || t.status == DownloadStatus.pending));

  DownloadTask? getTaskByEpisodeId(int episodeId) {
    try {
      return tasks.firstWhere((t) => t.episodeId == episodeId);
    } catch (_) {
      return null;
    }
  }
}

class DownloadManagerNotifier extends StateNotifier<DownloadManagerState> {
  final DownloadService _service;

  DownloadManagerNotifier(this._service) : super(const DownloadManagerState()) {
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

  void _updateTask(DownloadTask task) {
    final tasks = state.tasks.map((t) => t.id == task.id ? task : t).toList();
    state = state.copyWith(tasks: tasks);
    _saveTasks();
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

  void _startDownload(DownloadTask task) {
    _service.startDownload(
      task,
      (updated) => _updateTask(updated),
      (completed) {
        _updateTask(completed);
        _processNextInQueue();
      },
      (failed, error) {
        final updatedTask = failed.copyWith(
          status: DownloadStatus.failed,
          errorMessage: error,
        );
        _updateTask(updatedTask);
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
    _updateTask(task.copyWith(status: DownloadStatus.paused));
  }

  void resumeDownload(String taskId) {
    final task = state.tasks.firstWhere((t) => t.id == taskId);
    final updatedTask = task.copyWith(status: DownloadStatus.pending);
    _updateTask(updatedTask);
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
    _updateTask(updatedTask);
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

  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(hours: 2),
  ));

  return DownloadService(dio, serverUrl);
});

final downloadManagerProvider =
    StateNotifierProvider<DownloadManagerNotifier, DownloadManagerState>((ref) {
  final service = ref.watch(downloadServiceProvider);
  if (service == null) {
    return DownloadManagerNotifier(DownloadService(Dio(), ''));
  }
  return DownloadManagerNotifier(service);
});
