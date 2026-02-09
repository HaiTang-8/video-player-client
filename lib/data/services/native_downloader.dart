import 'dart:async';

import 'package:flutter/services.dart';

import 'log_service.dart';

class NativeDownloadProgress {
  final String taskId;
  final int downloadedBytes;
  final int totalBytes;
  final double speed;
  final int activeThreads;
  final String status; // downloading, completed, failed, paused

  NativeDownloadProgress({
    required this.taskId,
    required this.downloadedBytes,
    required this.totalBytes,
    required this.speed,
    required this.activeThreads,
    required this.status,
  });

  double get progress => totalBytes > 0 ? downloadedBytes / totalBytes : 0;

  factory NativeDownloadProgress.fromMap(Map<dynamic, dynamic> map) {
    return NativeDownloadProgress(
      taskId: map['taskId'] as String,
      downloadedBytes: map['downloadedBytes'] as int,
      totalBytes: map['totalBytes'] as int,
      speed: (map['speed'] as num).toDouble(),
      activeThreads: map['activeThreads'] as int,
      status: map['status'] as String,
    );
  }
}

class NativeDownloader {
  static const MethodChannel _channel = MethodChannel('media_player/downloader');
  static const EventChannel _progressChannel = EventChannel('media_player/downloader/progress');

  static NativeDownloader? _instance;
  static NativeDownloader get instance => _instance ??= NativeDownloader._();

  final Map<String, void Function(NativeDownloadProgress)> _progressCallbacks = {};
  final Map<String, void Function()> _completeCallbacks = {};
  final Map<String, void Function(String)> _errorCallbacks = {};

  StreamSubscription? _progressSubscription;

  NativeDownloader._() {
    _initProgressListener();
  }

  void _initProgressListener() {
    _progressSubscription = _progressChannel.receiveBroadcastStream().listen(
      (dynamic event) {
        if (event is Map) {
          final progress = NativeDownloadProgress.fromMap(event);
          final callback = _progressCallbacks[progress.taskId];

          if (progress.status == 'completed') {
            _completeCallbacks[progress.taskId]?.call();
            _cleanupCallbacks(progress.taskId);
          } else if (progress.status == 'failed') {
            final error = event['error'] as String? ?? 'Download failed';
            LogService.instance.error('NativeDownloader', 'Download failed: $error');
            _errorCallbacks[progress.taskId]?.call(error);
            _cleanupCallbacks(progress.taskId);
          } else {
            callback?.call(progress);
          }
        }
      },
      onError: (error) {
        LogService.instance.warn('NativeDownloader', 'Progress stream error: $error');
      },
    );
  }

  void _cleanupCallbacks(String taskId) {
    _progressCallbacks.remove(taskId);
    _completeCallbacks.remove(taskId);
    _errorCallbacks.remove(taskId);
  }

  void clearCallbacks() {
    _progressCallbacks.clear();
    _completeCallbacks.clear();
    _errorCallbacks.clear();
  }

  Future<bool> isAvailable() async {
    try {
      final result = await _channel.invokeMethod<bool>('isAvailable');
      return result ?? false;
    } catch (e) {
      LogService.instance.warn('NativeDownloader', 'isAvailable error: $e');
      return false;
    }
  }

  Future<String?> startDownload({
    required String taskId,
    required String url,
    required String savePath,
    String? displayName,
    Map<String, String>? headers,
    int threadCount = 8,
    void Function(NativeDownloadProgress)? onProgress,
    void Function()? onComplete,
    void Function(String error)? onError,
  }) async {
    try {
      if (onProgress != null) _progressCallbacks[taskId] = onProgress;
      if (onComplete != null) _completeCallbacks[taskId] = onComplete;
      if (onError != null) _errorCallbacks[taskId] = onError;

      final result = await _channel.invokeMethod<String>('startDownload', {
        'taskId': taskId,
        'url': url,
        'savePath': savePath,
        'displayName': displayName,
        'headers': headers ?? {},
        'threadCount': threadCount,
      });
      return result;
    } catch (e) {
      LogService.instance.error('NativeDownloader', 'startDownload error: $e');
      _cleanupCallbacks(taskId);
      onError?.call(e.toString());
      return null;
    }
  }

  Future<void> pauseDownload(String taskId) async {
    try {
      await _channel.invokeMethod('pauseDownload', {'taskId': taskId});
    } catch (e) {
      LogService.instance.warn('NativeDownloader', 'pauseDownload error: $e');
    }
  }

  Future<void> resumeDownload(String taskId) async {
    try {
      await _channel.invokeMethod('resumeDownload', {'taskId': taskId});
    } catch (e) {
      LogService.instance.warn('NativeDownloader', 'resumeDownload error: $e');
    }
  }

  Future<void> cancelDownload(String taskId) async {
    try {
      await _channel.invokeMethod('cancelDownload', {'taskId': taskId});
      _cleanupCallbacks(taskId);
    } catch (e) {
      LogService.instance.warn('NativeDownloader', 'cancelDownload error: $e');
    }
  }

  Future<bool> isLiveActivityEnabled() async {
    try {
      final result = await _channel.invokeMethod<bool>('isLiveActivityEnabled');
      return result ?? false;
    } catch (e) {
      LogService.instance.warn('NativeDownloader', 'isLiveActivityEnabled error: $e');
      return false;
    }
  }

  Future<void> endLiveActivity(String taskId, {String status = 'completed'}) async {
    try {
      await _channel.invokeMethod('endLiveActivity', {
        'taskId': taskId,
        'status': status,
      });
    } catch (e) {
      LogService.instance.warn('NativeDownloader', 'endLiveActivity error: $e');
    }
  }

  void dispose() {
    _progressSubscription?.cancel();
    _progressCallbacks.clear();
    _completeCallbacks.clear();
    _errorCallbacks.clear();
  }
}
