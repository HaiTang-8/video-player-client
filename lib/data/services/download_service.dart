import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/api_constants.dart';
import '../../core/utils/file_name_sanitizer.dart';
import '../../core/utils/http_utils.dart';
import '../models/download_task.dart';
import '../models/episode.dart';
import '../models/movie.dart';
import '../models/storage.dart';
import 'aria2_manager.dart';
import 'log_service.dart';
import 'multi_thread_downloader.dart';
import 'native_downloader.dart';

typedef ProgressCallback = void Function(int received, int total);

class DownloadService {
  static const MethodChannel _storageChannel = MethodChannel('media_player/storage');

  final Dio _dio;
  final String _serverUrl;
  final Map<String, CancelToken> _cancelTokens = {};
  final Map<String, MultiThreadDownloader> _multiThreadDownloaders = {};
  final Map<int, Storage> _storageCache = {};

  static const String tasksKey = 'download_tasks';

  // 多线程下载配置
  int threadCount = 8;
  bool useMultiThread = true;
  bool useNativeDownloader = true; // 优先使用原生下载器
  bool useAria2 = true; // PC端优先使用aria2

  // aria2 任务映射: taskId -> gid
  final Map<String, String> _aria2Tasks = {};
  Timer? _aria2ProgressTimer;

  DownloadService(this._dio, this._serverUrl);

  String? _cachedDownloadDir;

  Future<String> get _downloadDir async {
    final cached = _cachedDownloadDir;
    if (cached != null) return cached;

    final dir = await getApplicationDocumentsDirectory();
    final downloadDir = Directory('${dir.path}/downloads');
    if (!await downloadDir.exists()) {
      await downloadDir.create(recursive: true);
    }
    _cachedDownloadDir = downloadDir.path;

    // Avoid iCloud/iTunes backups for large video files.
    if (Platform.isIOS) {
      try {
        await _storageChannel.invokeMethod('excludeFromBackup', {'path': downloadDir.path});
      } catch (_) {
        // Best-effort only.
      }
    }

    return downloadDir.path;
  }

  Future<(String?, int?, String?, String?)> _fetchStreamUrl(
    int tvShowId,
    int seasonId,
    int episodeId, {
    String? userAgent,
  }) async {
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
              userAgent: userAgent,
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

  Future<(String?, int?, String?, String?)> _fetchMovieStreamUrl(
    int movieId, {
    String? userAgent,
  }) async {
    try {
      // 优先使用下载直链接口获取带客户端 IP 签名的 URL
      final downloadUrl = await _fetchDownloadUrl(
        ApiConstants.downloadMovieUrl(movieId),
        userAgent: userAgent,
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

  // aria2 使用的 User-Agent，必须与获取下载链接时一致
  static const String aria2UserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/87.0.4280.88 Safari/537.36 Edg/87.0.664.57';

  Future<String?> _fetchDownloadUrl(String apiPath, {String? userAgent}) async {
    try {
      final url = '$_serverUrl$apiPath';
      final queryParams = userAgent != null ? '?user_agent=${Uri.encodeComponent(userAgent)}' : '';
      final fullUrl = '$url$queryParams';
      if (kDebugMode) {
        LogService.instance.debug('DownloadService', 'requesting download url via apiPath=$apiPath');
      }
      final response = await _dio.get(fullUrl);
      if (response.statusCode == 200 && response.data != null) {
        final data = response.data['data'] as Map<String, dynamic>?;
        final downloadUrl = data?['url'] as String?;
        if (downloadUrl != null && downloadUrl.isNotEmpty) {
          return downloadUrl.startsWith('http') ? downloadUrl : '$_serverUrl$downloadUrl';
        }
      }
    } catch (e) {
      LogService.instance.warn('DownloadService', '_fetchDownloadUrl error: $e');
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

  Future<DownloadTask> createTask({
    required Episode episode,
    required String tvShowName,
    required int seasonNumber,
    String? storageName,
  }) async {
    final dir = await _downloadDir;
    final sanitizedTvShowName = sanitizeFileName(tvShowName);
    final fileName = episode.filePath?.split('/').last ?? 'episode_${episode.id}.mp4';
    final sanitizedFileName = sanitizeFileName(fileName);

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
    final sanitizedFileName = sanitizeFileName(fileName);

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

    // 使用固定的 User-Agent，确保获取链接和下载时一致（与 aria2 相同）
    const downloadUserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/87.0.4280.88 Safari/537.36 Edg/87.0.664.57';

    if (task.isMovie) {
      final result = await _fetchMovieStreamUrl(task.movieId!, userAgent: downloadUserAgent);
      streamUrl = result.$1;
      storageId = result.$2;
      fetchError = result.$4;
    } else {
      final result = await _fetchStreamUrl(
        task.tvShowId!,
        task.seasonId!,
        task.episodeId!,
        userAgent: downloadUserAgent,
      );
      streamUrl = result.$1;
      storageId = result.$2;
      fetchError = result.$4;
    }

    if (streamUrl == null) {
      onError(task, fetchError ?? '无法获取下载地址');
      return;
    }

    if (kDebugMode) {
      final safeUrl = Uri.tryParse(streamUrl);
      final safeUrlText = safeUrl == null
          ? '<invalid-url>'
          : '${safeUrl.scheme}://${safeUrl.host}${safeUrl.path}';
      LogService.instance.debug('DownloadService', '========== DOWNLOAD DEBUG ==========');
      LogService.instance.debug('DownloadService', 'Download URL: $safeUrlText');
      LogService.instance.debug('DownloadService', 'File: ${task.fileName}');
      LogService.instance.debug(
        'DownloadService',
        'Multi-thread: $useMultiThread, Threads: $threadCount',
      );
      LogService.instance.debug('DownloadService', 'Native downloader: $useNativeDownloader');
      LogService.instance.debug('DownloadService', '=====================================');
    }

    var updatedTask = task.copyWith(downloadUrl: streamUrl);

    // 构建 headers，包含 User-Agent
    final headers = <String, String>{
      'User-Agent': downloadUserAgent,
    };
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
          final targetUri = Uri.tryParse(streamUrl);
          if (HttpUtils.sameOrigin(webdavUri, targetUri)) {
            headers['Authorization'] = HttpUtils.basicAuthHeader(username, password);
          }
        }
      }
    }

    // 优先使用原生下载器（iOS/Android）
    if (useNativeDownloader && (Platform.isIOS || Platform.isAndroid)) {
      final nativeAvailable = await NativeDownloader.instance.isAvailable();
      if (nativeAvailable) {
        LogService.instance.info('DownloadService', 'Using native downloader');
        await _startNativeDownload(
          task: updatedTask,
          url: streamUrl,
          headers: headers,
          onProgress: onProgress,
          onComplete: onComplete,
          onError: onError,
        );
        return;
      }
    }

    // PC端优先使用aria2
    if (useAria2 && (Platform.isWindows || Platform.isMacOS)) {
      final aria2 = Aria2Manager.instance;
      if (aria2.isRunning && aria2.service != null) {
        LogService.instance.info('DownloadService', 'Using aria2 downloader');
        await _startAria2Download(
          task: updatedTask,
          url: streamUrl,
          headers: headers,
          onProgress: onProgress,
          onComplete: onComplete,
          onError: onError,
        );
        return;
      }
    }

    if (useMultiThread) {
      await _startMultiThreadDownload(
        task: updatedTask,
        url: streamUrl,
        headers: headers,
        onProgress: onProgress,
        onComplete: onComplete,
        onError: onError,
      );
    } else {
      await _startSingleThreadDownload(
        task: updatedTask,
        url: streamUrl,
        headers: headers,
        onProgress: onProgress,
        onComplete: onComplete,
        onError: onError,
      );
    }
  }

  Future<void> _startNativeDownload({
    required DownloadTask task,
    required String url,
    required Map<String, String> headers,
    required void Function(DownloadTask) onProgress,
    required void Function(DownloadTask) onComplete,
    required void Function(DownloadTask, String) onError,
  }) async {
    var updatedTask = task.copyWith(status: DownloadStatus.downloading);
    onProgress(updatedTask);

    // 确保目录存在
    final file = File(task.localPath);
    final parentDir = file.parent;
    if (!await parentDir.exists()) {
      await parentDir.create(recursive: true);
    }

    await NativeDownloader.instance.startDownload(
      taskId: task.id,
      url: url,
      savePath: task.localPath,
      displayName: task.liveActivityTitle,
      headers: headers,
      threadCount: threadCount,
      onProgress: (progress) {
        final status = progress.status == 'paused'
            ? DownloadStatus.paused
            : DownloadStatus.downloading;
        updatedTask = updatedTask.copyWith(
          status: status,
          progress: progress.progress,
          downloadedBytes: progress.downloadedBytes,
          fileSize: progress.totalBytes > 0 ? progress.totalBytes : updatedTask.fileSize,
          downloadSpeed: progress.speed,
        );
        onProgress(updatedTask);
      },
      onComplete: () {
        updatedTask = updatedTask.copyWith(
          status: DownloadStatus.completed,
          progress: 1.0,
          completedAt: DateTime.now(),
        );
        onComplete(updatedTask);
      },
      onError: (error) {
        onError(updatedTask, error);
      },
    );
  }

  Future<void> _startAria2Download({
    required DownloadTask task,
    required String url,
    required Map<String, String> headers,
    required void Function(DownloadTask) onProgress,
    required void Function(DownloadTask) onComplete,
    required void Function(DownloadTask, String) onError,
  }) async {
    final aria2 = Aria2Manager.instance.service;
    if (aria2 == null) {
      onError(task, 'aria2 service is not available (not running)');
      return;
    }
    var updatedTask = task.copyWith(status: DownloadStatus.downloading);
    onProgress(updatedTask);

    final file = File(task.localPath);
    final dir = file.parent.path;
    final filename = file.uri.pathSegments.last;

    try {
      final gid = await aria2.addUri(url, dir: dir, filename: filename, headers: headers);
      _aria2Tasks[task.id] = gid;

      _aria2ProgressTimer?.cancel();
      _aria2ProgressTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
        await _pollAria2Progress(onProgress, onComplete, onError);
      });
    } catch (e) {
      onError(updatedTask, e.toString());
    }
  }

  Future<void> _pollAria2Progress(
    void Function(DownloadTask) onProgress,
    void Function(DownloadTask) onComplete,
    void Function(DownloadTask, String) onError,
  ) async {
    final aria2 = Aria2Manager.instance.service;
    if (aria2 == null) return;

    final tasks = await loadTasks();
    final toRemove = <String>[];

    for (final entry in _aria2Tasks.entries) {
      final taskId = entry.key;
      final gid = entry.value;

      try {
        final status = await aria2.tellStatus(gid);
        final task = tasks.firstWhere((t) => t.id == taskId, orElse: () => throw StateError('Task not found'));

        final completedLength = int.tryParse(status['completedLength']?.toString() ?? '0') ?? 0;
        final totalLength = int.tryParse(status['totalLength']?.toString() ?? '0') ?? 0;
        final downloadSpeed = int.tryParse(status['downloadSpeed']?.toString() ?? '0') ?? 0;
        final aria2Status = status['status'] as String?;

        final progress = totalLength > 0 ? completedLength / totalLength : 0.0;
        var updatedTask = task.copyWith(
          progress: progress,
          downloadedBytes: completedLength,
          fileSize: totalLength > 0 ? totalLength : task.fileSize,
          downloadSpeed: downloadSpeed.toDouble(),
        );

        if (aria2Status == 'complete') {
          updatedTask = updatedTask.copyWith(
            status: DownloadStatus.completed,
            progress: 1.0,
            completedAt: DateTime.now(),
          );
          onComplete(updatedTask);
          toRemove.add(taskId);
        } else if (aria2Status == 'error') {
          final errorMsg = status['errorMessage'] as String? ?? 'Download failed';
          onError(updatedTask, errorMsg);
          toRemove.add(taskId);
        } else {
          onProgress(updatedTask);
        }
      } catch (_) {
        toRemove.add(taskId);
      }
    }

    for (final id in toRemove) {
      _aria2Tasks.remove(id);
    }

    if (_aria2Tasks.isEmpty) {
      _aria2ProgressTimer?.cancel();
      _aria2ProgressTimer = null;
    }
  }

  Future<void> _startMultiThreadDownload({
    required DownloadTask task,
    required String url,
    required Map<String, String> headers,
    required void Function(DownloadTask) onProgress,
    required void Function(DownloadTask) onComplete,
    required void Function(DownloadTask, String) onError,
  }) async {
    final downloader = MultiThreadDownloader(
      dio: _dio,
      threadCount: threadCount,
    );
    _multiThreadDownloaders[task.id] = downloader;

    var updatedTask = task.copyWith(status: DownloadStatus.downloading);
    onProgress(updatedTask);

    await downloader.download(
      url: url,
      savePath: task.localPath,
      headers: headers.isNotEmpty ? headers : null,
      onProgress: (progress) {
        updatedTask = updatedTask.copyWith(
          progress: progress.progress,
          downloadedBytes: progress.downloadedBytes,
          fileSize: progress.totalBytes > 0 ? progress.totalBytes : updatedTask.fileSize,
          downloadSpeed: progress.speed,
        );
        onProgress(updatedTask);
      },
      onComplete: () {
        _multiThreadDownloaders.remove(task.id);
        updatedTask = updatedTask.copyWith(
          status: DownloadStatus.completed,
          progress: 1.0,
          completedAt: DateTime.now(),
        );
        onComplete(updatedTask);
      },
      onError: (error) {
        _multiThreadDownloaders.remove(task.id);
        onError(updatedTask, error);
      },
    );
  }

  Future<void> _startSingleThreadDownload({
    required DownloadTask task,
    required String url,
    required Map<String, String> headers,
    required void Function(DownloadTask) onProgress,
    required void Function(DownloadTask) onComplete,
    required void Function(DownloadTask, String) onError,
  }) async {
    var updatedTask = task;
    final cancelToken = CancelToken();
    _cancelTokens[task.id] = cancelToken;

    IOSink? sink;
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

      final requestHeaders = <String, dynamic>{...headers};
      if (downloadedBytes > 0) {
        requestHeaders['Range'] = 'bytes=$downloadedBytes-';
      }

      final options = Options(
        headers: requestHeaders.isEmpty ? null : requestHeaders,
        responseType: ResponseType.stream,
        validateStatus: (status) => status == 200 || status == 206 || status == 416,
      );

      var response = await _dio.get<ResponseBody>(
        url,
        options: options,
        cancelToken: cancelToken,
      );

      var effectiveDownloadedBytes = downloadedBytes;
      final statusCode = response.statusCode ?? 0;

      // Range resume safety: never blindly append unless the server confirms partial content.
      if (downloadedBytes > 0) {
        if (statusCode == 200) {
          // Server ignored Range and returned the full content; restart from scratch.
          effectiveDownloadedBytes = 0;
        } else if (statusCode == 206) {
          final contentRange = response.headers.value('content-range');
          final match = RegExp(r'^bytes (\d+)-').firstMatch(contentRange ?? '');
          final start = match != null ? int.tryParse(match.group(1)!) : null;
          if (start == null || start != downloadedBytes) {
            try {
              await file.delete();
            } catch (e) {
              LogService.instance.warn('DownloadService', 'Failed to delete file on resume mismatch: $e');
            }
            onError(updatedTask, 'Resume validation failed (Content-Range mismatch)');
            return;
          }
        } else if (statusCode == 416) {
          // Local partial is invalid (e.g. remote changed). Restart download from scratch.
          try {
            await response.data?.stream.drain();
          } catch (e) {
            LogService.instance.warn('DownloadService', 'Failed to drain stream: $e');
          }
          try {
            if (await file.exists()) await file.delete();
          } catch (e) {
            LogService.instance.warn('DownloadService', 'Failed to delete invalid partial file: $e');
          }
          effectiveDownloadedBytes = 0;
          response = await _dio.get<ResponseBody>(
            url,
            options: Options(
              headers: headers.isEmpty ? null : headers,
              responseType: ResponseType.stream,
              validateStatus: (status) => status == 200 || status == 206,
            ),
            cancelToken: cancelToken,
          );
        }
      }

      final totalBytes = _parseContentLength(response, effectiveDownloadedBytes);

      downloadedBytes = effectiveDownloadedBytes;
      sink = file.openWrite(mode: downloadedBytes > 0 ? FileMode.append : FileMode.write);

      updatedTask = updatedTask.copyWith(
        status: DownloadStatus.downloading,
        downloadedBytes: downloadedBytes,
        fileSize: totalBytes > 0 ? totalBytes : updatedTask.fileSize,
      );
      onProgress(updatedTask);

      var lastUpdateTime = DateTime.now();
      var lastBytes = downloadedBytes;
      double smoothedSpeed = 0;
      const double alpha = 0.3;
      bool isFirstSpeedCalc = true;

      await for (final chunk in response.data!.stream) {
        if (cancelToken.isCancelled) break;

        sink.add(chunk);
        downloadedBytes += chunk.length;

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
      LogService.instance.error('DownloadService', 'DioException: ${e.type}, message=${e.message}');
      onError(updatedTask, e.message ?? '下载失败');
    } catch (e) {
      LogService.instance.error('DownloadService', 'Exception: $e');
      onError(updatedTask, e.toString());
    } finally {
      try {
        await sink?.flush();
        await sink?.close();
      } catch (e) {
        LogService.instance.warn('DownloadService', 'Failed to close file sink: $e');
      }
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
    // aria2 下载
    final gid = _aria2Tasks[taskId];
    if (gid != null) {
      Aria2Manager.instance.service?.pause(gid);
      return;
    }
    // 原生下载器
    if (Platform.isIOS || Platform.isAndroid) {
      NativeDownloader.instance.pauseDownload(taskId);
    }
    // 多线程下载器
    final multiDownloader = _multiThreadDownloaders[taskId];
    if (multiDownloader != null) {
      multiDownloader.pause();
      return;
    }
    // 单线程下载
    _cancelTokens[taskId]?.cancel('paused');
    _cancelTokens.remove(taskId);
  }

  void resumeDownload(String taskId) {
    // aria2 下载
    final gid = _aria2Tasks[taskId];
    if (gid != null) {
      Aria2Manager.instance.service?.unpause(gid);
      return;
    }
    // 原生下载器
    if (Platform.isIOS || Platform.isAndroid) {
      NativeDownloader.instance.resumeDownload(taskId);
    }
    final multiDownloader = _multiThreadDownloaders[taskId];
    if (multiDownloader != null) {
      multiDownloader.resume();
    }
  }

  void cancelDownload(String taskId) {
    // aria2 下载
    final gid = _aria2Tasks[taskId];
    if (gid != null) {
      Aria2Manager.instance.service?.remove(gid);
      _aria2Tasks.remove(taskId);
      return;
    }
    // 原生下载器
    if (Platform.isIOS || Platform.isAndroid) {
      NativeDownloader.instance.cancelDownload(taskId);
    }
    // 多线程下载器
    final multiDownloader = _multiThreadDownloaders[taskId];
    if (multiDownloader != null) {
      multiDownloader.cancel();
      _multiThreadDownloaders.remove(taskId);
      return;
    }
    // 单线程下载
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
      } catch (e) {
        LogService.instance.warn('DownloadService', 'Delete failed, retrying: $e');
        await Future.delayed(const Duration(milliseconds: 200));
        try {
          await file.delete();
        } catch (e2) {
          LogService.instance.warn('DownloadService', 'Delete retry failed: $e2');
        }
      }
    }

    // 删除多线程下载的临时分片目录
    final partsDir = Directory('${task.localPath}.parts');
    if (await partsDir.exists()) {
      try {
        await partsDir.delete(recursive: true);
      } catch (e) {
        LogService.instance.warn('DownloadService', 'Failed to delete parts dir: $e');
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
      final jsonStr = prefs.getString(tasksKey);
      if (jsonStr == null) return [];

      final list = jsonDecode(jsonStr) as List;
      final tasks = list.map((e) => DownloadTask.fromJson(e as Map<String, dynamic>)).toList();

      // Reconcile persisted state with filesystem (e.g. files deleted via storage cleanup).
      var changed = false;
      final reconciled = <DownloadTask>[];
      for (final task in tasks) {
        if (task.status == DownloadStatus.completed) {
          final exists = await File(task.localPath).exists();
          if (!exists) {
            changed = true;
            reconciled.add(task.copyWith(
              status: DownloadStatus.failed,
              errorMessage: 'Local file missing',
              progress: 0,
              downloadedBytes: 0,
              completedAt: null,
            ));
            continue;
          }
        }
        reconciled.add(task);
      }

      if (changed) {
        await saveTasks(reconciled);
      }

      return reconciled;
    } catch (e) {
      LogService.instance.warn('DownloadService', 'Failed to load download tasks: $e');
      return [];
    }
  }

  Future<void> saveTasks(List<DownloadTask> tasks) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = jsonEncode(tasks.map((t) => t.toJson()).toList());
      await prefs.setString(tasksKey, jsonStr);
    } catch (e) {
      LogService.instance.warn('DownloadService', 'Failed to save download tasks: $e');
    }
  }

  Future<int> getAvailableSpace() async {
    if (!(Platform.isIOS || Platform.isAndroid)) return 0;
    try {
      final value = await _storageChannel.invokeMethod<num>('getAvailableSpace');
      return value?.toInt() ?? 0;
    } catch (_) {
      return 0;
    }
  }

  Future<({String? url, Map<String, String> headers, String? error})> getDownloadInfo(
    DownloadTask task, {
    String? userAgent,
  }) async {
    String? streamUrl;
    int? storageId;
    String? fetchError;

    if (task.isMovie) {
      final result = await _fetchMovieStreamUrl(task.movieId!, userAgent: userAgent);
      streamUrl = result.$1;
      storageId = result.$2;
      fetchError = result.$4;
    } else {
      final result = await _fetchStreamUrl(
        task.tvShowId!,
        task.seasonId!,
        task.episodeId!,
        userAgent: userAgent,
      );
      streamUrl = result.$1;
      storageId = result.$2;
      fetchError = result.$4;
    }

    if (streamUrl == null) {
      return (url: null, headers: <String, String>{}, error: fetchError ?? '无法获取下载地址');
    }

    final headers = <String, String>{};
    // 如果指定了 userAgent，添加到 headers 中
    if (userAgent != null) {
      headers['User-Agent'] = userAgent;
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
          final targetUri = Uri.tryParse(streamUrl);
          if (HttpUtils.sameOrigin(webdavUri, targetUri)) {
            headers['Authorization'] = HttpUtils.basicAuthHeader(username, password);
          }
        }
      }
    }

    return (url: streamUrl, headers: headers, error: null);
  }

  Future<String> getDownloadDir() => _downloadDir;
}
