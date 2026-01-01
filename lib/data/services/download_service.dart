import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/api_constants.dart';
import '../models/download_task.dart';
import '../models/episode.dart';
import '../models/movie.dart';
import '../models/storage.dart';

typedef ProgressCallback = void Function(int received, int total);

class DownloadService {
  final Dio _dio;
  final String _serverUrl;
  final Map<String, CancelToken> _cancelTokens = {};
  final Map<int, Storage> _storageCache = {};

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

  Future<(String?, int?, String?, String?)> _fetchStreamUrl(
    int tvShowId,
    int seasonId,
    int episodeId,
  ) async {
    try {
      final response = await _dio.get(
        '$_serverUrl${ApiConstants.episodeStream(tvShowId, seasonId, episodeId)}',
      );
      if (response.statusCode == 200 && response.data != null) {
        final data = response.data['data'] as Map<String, dynamic>?;
        if (data != null) {
          final storageId = data['storage_id'] as int?;
          final filePath = data['file_path'] as String?;
          final sourceId = data['source_id'] as int?;

          // 优先使用下载直链接口获取带客户端 IP 签名的 URL
          if (sourceId != null) {
            final downloadUrl = await _fetchDownloadUrl(
              ApiConstants.downloadSourceUrl(sourceId),
            );
            if (downloadUrl != null) {
              return (downloadUrl, storageId, filePath, null);
            }
          }

          // 兜底：使用 safe_url
          final url = data['safe_url'] as String? ?? data['url'] as String?;
          if (url != null && url.isNotEmpty) {
            final fullUrl = url.startsWith('http') ? url : '$_serverUrl$url';
            return (fullUrl, storageId, filePath, null);
          }
        }
      }
      return (null, null, null, '服务器返回数据格式错误');
    } on DioException catch (e) {
      return (null, null, null, e.message ?? '网络请求失败: ${e.type}');
    } catch (e) {
      return (null, null, null, '获取下载地址失败: $e');
    }
  }

  Future<(String?, int?, String?, String?)> _fetchMovieStreamUrl(int movieId) async {
    try {
      // 优先使用下载直链接口获取带客户端 IP 签名的 URL
      final downloadUrl = await _fetchDownloadUrl(
        ApiConstants.downloadMovieUrl(movieId),
      );

      final response = await _dio.get(
        '$_serverUrl${ApiConstants.movieStream(movieId)}',
      );
      if (response.statusCode == 200 && response.data != null) {
        final data = response.data['data'] as Map<String, dynamic>?;
        if (data != null) {
          final storageId = data['storage_id'] as int?;
          final filePath = data['file_path'] as String?;

          if (downloadUrl != null) {
            return (downloadUrl, storageId, filePath, null);
          }

          // 兜底：使用 safe_url
          final url = data['safe_url'] as String? ?? data['url'] as String?;
          if (url != null && url.isNotEmpty) {
            final fullUrl = url.startsWith('http') ? url : '$_serverUrl$url';
            return (fullUrl, storageId, filePath, null);
          }
        }
      }
      return (null, null, null, '服务器返回数据格式错误');
    } on DioException catch (e) {
      return (null, null, null, e.message ?? '网络请求失败: ${e.type}');
    } catch (e) {
      return (null, null, null, '获取下载地址失败: $e');
    }
  }

  // TODO: 暂不使用公网 IP 功能，115 只需要 User-Agent
  // String? _cachedPublicIP;
  // DateTime? _publicIPCacheTime;

  // Future<String?> _getPublicIP() async {
  //   // 缓存 5 分钟
  //   if (_cachedPublicIP != null && _publicIPCacheTime != null) {
  //     if (DateTime.now().difference(_publicIPCacheTime!).inMinutes < 5) {
  //       return _cachedPublicIP;
  //     }
  //   }

  //   // 多个备用服务
  //   final services = [
  //     'https://api.ipify.org',
  //     'https://ifconfig.me/ip',
  //     'https://icanhazip.com',
  //     'https://api.ip.sb/ip',
  //   ];

  //   for (final service in services) {
  //     try {
  //       debugPrint('[DownloadService] trying to get IP from: $service');
  //       final response = await _dio.get(
  //         service,
  //         options: Options(
  //           receiveTimeout: const Duration(seconds: 5),
  //           sendTimeout: const Duration(seconds: 5),
  //         ),
  //       );
  //       if (response.statusCode == 200 && response.data != null) {
  //         final ip = response.data.toString().trim();
  //         if (ip.isNotEmpty && RegExp(r'^\d+\.\d+\.\d+\.\d+$').hasMatch(ip)) {
  //           _cachedPublicIP = ip;
  //           _publicIPCacheTime = DateTime.now();
  //           debugPrint('[DownloadService] got public IP: $ip from $service');
  //           return _cachedPublicIP;
  //         }
  //       }
  //     } catch (e) {
  //       debugPrint('[DownloadService] failed to get IP from $service: $e');
  //     }
  //   }
  //   return null;
  // }

  Future<String?> _fetchDownloadUrl(String apiPath) async {
    try {
      // TODO: 暂不使用公网 IP，115 只需要 User-Agent
      // final publicIP = await _getPublicIP();
      // final queryParams = publicIP != null ? '?client_ip=$publicIP' : '';
      final url = '$_serverUrl$apiPath';
      debugPrint('[DownloadService] requesting: $url');
      final response = await _dio.get(url);
      if (response.statusCode == 200 && response.data != null) {
        final data = response.data['data'] as Map<String, dynamic>?;
        final downloadUrl = data?['url'] as String?;
        debugPrint('[DownloadService] downloadUrl=$downloadUrl');
        if (downloadUrl != null && downloadUrl.isNotEmpty) {
          return downloadUrl;
        }
      }
    } catch (e) {
      debugPrint('[DownloadService] _fetchDownloadUrl error: $e');
    }
    return null;
  }

  Future<Storage?> _getStorageById(int storageId) async {
    final cached = _storageCache[storageId];
    if (cached != null) return cached;

    try {
      final response = await _dio.get('$_serverUrl${ApiConstants.storages}');
      if (response.statusCode == 200 && response.data != null) {
        final data = response.data['data'];
        if (data is List) {
          for (final item in data) {
            if (item is! Map<String, dynamic>) continue;
            final storage = Storage.fromJson(item);
            _storageCache[storage.id] = storage;
          }
        }
      }
    } catch (_) {
      // Ignore; fall through
    }

    return _storageCache[storageId];
  }

  String _basicAuthHeader(String username, String password) {
    final token = base64Encode(utf8.encode('$username:$password'));
    return 'Basic $token';
  }

  int _effectivePort(Uri uri) {
    if (uri.hasPort && uri.port > 0) return uri.port;
    switch (uri.scheme.toLowerCase()) {
      case 'https':
        return 443;
      case 'http':
        return 80;
      default:
        return uri.port;
    }
  }

  bool _sameOrigin(Uri? a, Uri? b) {
    if (a == null || b == null) return false;
    if (a.scheme.toLowerCase() != b.scheme.toLowerCase()) return false;
    if (a.host.toLowerCase() != b.host.toLowerCase()) return false;
    return _effectivePort(a) == _effectivePort(b);
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
      type: DownloadType.episode,
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
      downloadUrl: '',
      localPath: localPath,
      status: DownloadStatus.pending,
      createdAt: DateTime.now(),
    );

    return task;
  }

  Future<DownloadTask> createMovieTask({
    required Movie movie,
  }) async {
    final dir = await _downloadDir;
    final fileName = movie.filePath?.split('/').last ?? 'movie_${movie.id}.mp4';
    final sanitizedFileName = _sanitizeFileName(fileName);

    final localPath = '$dir/Movies/$sanitizedFileName';

    final task = DownloadTask(
      id: 'movie_${movie.id}_${DateTime.now().millisecondsSinceEpoch}',
      type: DownloadType.movie,
      movieId: movie.id,
      movieTitle: movie.title,
      fileName: fileName,
      fileSize: movie.fileSize,
      runtime: movie.runtime,
      storageName: movie.storageName,
      downloadUrl: '',
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
    String? streamUrl;
    int? storageId;
    String? fetchError;

    if (task.isMovie) {
      final result = await _fetchMovieStreamUrl(task.movieId!);
      streamUrl = result.$1;
      storageId = result.$2;
      fetchError = result.$4;
    } else {
      final result = await _fetchStreamUrl(
        task.tvShowId!,
        task.seasonId!,
        task.episodeId!,
      );
      streamUrl = result.$1;
      storageId = result.$2;
      fetchError = result.$4;
    }

    if (streamUrl == null) {
      onError(task, fetchError ?? '无法获取下载地址');
      return;
    }

    debugPrint('[DownloadService] startDownload streamUrl=$streamUrl');

    // Update task with the actual download URL
    var updatedTask = task.copyWith(downloadUrl: streamUrl);

    final cancelToken = CancelToken();
    _cancelTokens[task.id] = cancelToken;

    IOSink? sink;
    try {
      final file = File(updatedTask.localPath);
      final parentDir = file.parent;
      if (!await parentDir.exists()) {
        await parentDir.create(recursive: true);
      }

      int downloadedBytes = 0;
      if (await file.exists()) {
        downloadedBytes = await file.length();
      }

      final targetUrl = updatedTask.downloadUrl;

      // 仅在"目标 host 与 WebDAV host 一致"时才附带 BasicAuth，避免把凭证带到 CDN/第三方直链上。
      final headers = <String, dynamic>{};
      if (downloadedBytes > 0) {
        headers['Range'] = 'bytes=$downloadedBytes-';
      }
      if (storageId != null) {
        final storage = await _getStorageById(storageId);
        if (storage?.type.toLowerCase() == 'webdav') {
          final settings = storage?.settings;
          final webdavUrl = settings?['url'];
          final username = settings?['username'];
          final password = settings?['password'];
          if (webdavUrl != null &&
              username != null &&
              password != null &&
              username.isNotEmpty) {
            final webdavUri = Uri.tryParse(webdavUrl);
            final targetUri = Uri.tryParse(targetUrl);
            if (_sameOrigin(webdavUri, targetUri)) {
              headers['Authorization'] = _basicAuthHeader(username, password);
            }
          }
        }
      }

      final options = Options(
        headers: headers.isEmpty ? null : headers,
        responseType: ResponseType.stream,
      );

      final response = await _dio.get<ResponseBody>(
        targetUrl,
        options: options,
        cancelToken: cancelToken,
      );

      final totalBytes = _parseContentLength(response, downloadedBytes);

      sink = file.openWrite(mode: downloadedBytes > 0 ? FileMode.append : FileMode.write);

      updatedTask = updatedTask.copyWith(
        status: DownloadStatus.downloading,
        downloadedBytes: downloadedBytes,
        fileSize: totalBytes > 0 ? totalBytes : updatedTask.fileSize,
      );
      onProgress(updatedTask);

      // Speed calculation variables (Exponential Moving Average)
      var lastUpdateTime = DateTime.now();
      var lastBytes = downloadedBytes;
      double smoothedSpeed = 0;
      const double alpha = 0.3;
      bool isFirstSpeedCalc = true;

      await for (final chunk in response.data!.stream) {
        if (cancelToken.isCancelled) break;

        sink.add(chunk);
        downloadedBytes += chunk.length;

        // Calculate speed every 500ms using EMA
        final now = DateTime.now();
        final elapsed = now.difference(lastUpdateTime).inMilliseconds;
        if (elapsed >= 500) {
          final bytesDiff = downloadedBytes - lastBytes;
          final instantSpeed = bytesDiff / (elapsed / 1000);
          if (isFirstSpeedCalc) {
            smoothedSpeed = instantSpeed;
            isFirstSpeedCalc = false;
          } else {
            smoothedSpeed = alpha * instantSpeed + (1 - alpha) * smoothedSpeed;
          }
          lastUpdateTime = now;
          lastBytes = downloadedBytes;
        }

        final progress = totalBytes > 0 ? downloadedBytes / totalBytes : 0.0;
        updatedTask = updatedTask.copyWith(
          progress: progress,
          downloadedBytes: downloadedBytes,
          downloadSpeed: smoothedSpeed,
        );
        onProgress(updatedTask);
      }

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
      debugPrint('[DownloadService] DioException: ${e.type}, message=${e.message}, statusCode=${e.response?.statusCode}');
      debugPrint('[DownloadService] Response data: ${e.response?.data}');
      onError(updatedTask, e.message ?? '下载失败');
    } catch (e) {
      debugPrint('[DownloadService] Exception: $e');
      onError(updatedTask, e.toString());
    } finally {
      // 确保文件流被正确关闭
      try {
        await sink?.flush();
        await sink?.close();
      } catch (_) {}
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
    // 等待文件流关闭
    await Future.delayed(const Duration(milliseconds: 100));

    final file = File(task.localPath);
    if (await file.exists()) {
      try {
        await file.delete();
      } catch (_) {
        // 文件可能仍被占用，稍后重试
        await Future.delayed(const Duration(milliseconds: 200));
        try {
          await file.delete();
        } catch (_) {}
      }
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
