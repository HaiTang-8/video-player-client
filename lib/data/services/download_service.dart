import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/download_task.dart';
import '../models/episode.dart';

typedef ProgressCallback = void Function(int received, int total);

class DownloadService {
  final Dio _dio;
  final String _serverUrl;
  final Map<String, CancelToken> _cancelTokens = {};

  static const String _tasksKey = 'download_tasks';

  DownloadService(this._dio, this._serverUrl);

  Future<String> get _downloadDir async {
    final dir = await getApplicationDocumentsDirectory();
    final downloadDir = Directory('${dir.path}/downloads');
    if (!await downloadDir.exists()) {
      await downloadDir.create(recursive: true);
    }
    return downloadDir.path;
  }

  String _buildDownloadUrl(int episodeId) {
    return '$_serverUrl/api/v1/stream/episode/$episodeId';
  }

  String _sanitizeFileName(String fileName) {
    return fileName.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
  }

  Future<DownloadTask> createTask({
    required Episode episode,
    required String tvShowName,
    required int seasonNumber,
    String? storageName,
  }) async {
    final dir = await _downloadDir;
    final sanitizedTvShowName = _sanitizeFileName(tvShowName);
    final fileName = episode.filePath?.split('/').last ?? 'episode_${episode.id}.mp4';
    final sanitizedFileName = _sanitizeFileName(fileName);

    final localPath = '$dir/$sanitizedTvShowName/S${seasonNumber.toString().padLeft(2, '0')}/$sanitizedFileName';

    final task = DownloadTask(
      id: 'ep_${episode.id}_${DateTime.now().millisecondsSinceEpoch}',
      episodeId: episode.id,
      tvShowId: episode.tvShowId,
      seasonId: episode.seasonId,
      seasonNumber: seasonNumber,
      episodeNumber: episode.episodeNumber,
      episodeName: episode.name ?? '第 ${episode.episodeNumber} 集',
      tvShowName: tvShowName,
      fileName: fileName,
      fileSize: episode.fileSize,
      runtime: episode.runtime,
      storageName: storageName,
      downloadUrl: _buildDownloadUrl(episode.id),
      localPath: localPath,
      status: DownloadStatus.pending,
      createdAt: DateTime.now(),
    );

    return task;
  }

  Future<void> startDownload(
    DownloadTask task,
    void Function(DownloadTask) onProgress,
    void Function(DownloadTask) onComplete,
    void Function(DownloadTask, String) onError,
  ) async {
    final cancelToken = CancelToken();
    _cancelTokens[task.id] = cancelToken;

    try {
      final file = File(task.localPath);
      final parentDir = file.parent;
      if (!await parentDir.exists()) {
        await parentDir.create(recursive: true);
      }

      int downloadedBytes = 0;
      if (await file.exists()) {
        downloadedBytes = await file.length();
      }

      final options = Options(
        headers: downloadedBytes > 0 ? {'Range': 'bytes=$downloadedBytes-'} : null,
        responseType: ResponseType.stream,
      );

      final response = await _dio.get<ResponseBody>(
        task.downloadUrl,
        options: options,
        cancelToken: cancelToken,
      );

      final totalBytes = _parseContentLength(response, downloadedBytes);

      final sink = file.openWrite(mode: downloadedBytes > 0 ? FileMode.append : FileMode.write);

      var updatedTask = task.copyWith(
        status: DownloadStatus.downloading,
        downloadedBytes: downloadedBytes,
        fileSize: totalBytes > 0 ? totalBytes : task.fileSize,
      );
      onProgress(updatedTask);

      await for (final chunk in response.data!.stream) {
        if (cancelToken.isCancelled) break;

        sink.add(chunk);
        downloadedBytes += chunk.length;

        final progress = totalBytes > 0 ? downloadedBytes / totalBytes : 0.0;
        updatedTask = updatedTask.copyWith(
          progress: progress,
          downloadedBytes: downloadedBytes,
        );
        onProgress(updatedTask);
      }

      await sink.flush();
      await sink.close();

      if (!cancelToken.isCancelled) {
        updatedTask = updatedTask.copyWith(
          status: DownloadStatus.completed,
          progress: 1.0,
          completedAt: DateTime.now(),
        );
        onComplete(updatedTask);
      }
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        return;
      }
      onError(task, e.message ?? '下载失败');
    } catch (e) {
      onError(task, e.toString());
    } finally {
      _cancelTokens.remove(task.id);
    }
  }

  int _parseContentLength(Response<ResponseBody> response, int downloadedBytes) {
    final contentRange = response.headers.value('content-range');
    if (contentRange != null) {
      final match = RegExp(r'/(\d+)').firstMatch(contentRange);
      if (match != null) {
        return int.parse(match.group(1)!);
      }
    }
    final contentLength = response.headers.value('content-length');
    if (contentLength != null) {
      return int.parse(contentLength) + downloadedBytes;
    }
    return 0;
  }

  void pauseDownload(String taskId) {
    _cancelTokens[taskId]?.cancel('paused');
    _cancelTokens.remove(taskId);
  }

  void cancelDownload(String taskId) {
    _cancelTokens[taskId]?.cancel('cancelled');
    _cancelTokens.remove(taskId);
  }

  Future<void> deleteDownload(DownloadTask task) async {
    cancelDownload(task.id);
    final file = File(task.localPath);
    if (await file.exists()) {
      await file.delete();
    }

    final parentDir = file.parent;
    if (await parentDir.exists()) {
      final remaining = await parentDir.list().length;
      if (remaining == 0) {
        await parentDir.delete();
      }
    }
  }

  Future<bool> isDownloaded(int episodeId) async {
    final tasks = await loadTasks();
    return tasks.any((t) => t.episodeId == episodeId && t.status == DownloadStatus.completed);
  }

  Future<DownloadTask?> getTaskByEpisodeId(int episodeId) async {
    final tasks = await loadTasks();
    try {
      return tasks.firstWhere((t) => t.episodeId == episodeId);
    } catch (_) {
      return null;
    }
  }

  Future<List<DownloadTask>> loadTasks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_tasksKey);
      if (jsonStr == null) return [];

      final list = jsonDecode(jsonStr) as List;
      return list.map((e) => DownloadTask.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      debugPrint('Failed to load download tasks: $e');
      return [];
    }
  }

  Future<void> saveTasks(List<DownloadTask> tasks) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = jsonEncode(tasks.map((t) => t.toJson()).toList());
      await prefs.setString(_tasksKey, jsonStr);
    } catch (e) {
      debugPrint('Failed to save download tasks: $e');
    }
  }

  Future<int> getAvailableSpace() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      if (Platform.isIOS || Platform.isMacOS) {
        final stat = await FileStat.stat(dir.path);
        return stat.size;
      }
      return 0;
    } catch (e) {
      return 0;
    }
  }
}
