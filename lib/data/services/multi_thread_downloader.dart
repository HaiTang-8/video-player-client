import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class DownloadProgress {
  final int downloadedBytes;
  final int totalBytes;
  final double speed;
  final int activeThreads;

  DownloadProgress({
    required this.downloadedBytes,
    required this.totalBytes,
    required this.speed,
    required this.activeThreads,
  });

  double get progress => totalBytes > 0 ? downloadedBytes / totalBytes : 0;
}

class DownloadChunk {
  final int index;
  final int start;
  final int end;
  int downloaded;
  bool completed;

  DownloadChunk({
    required this.index,
    required this.start,
    required this.end,
    this.downloaded = 0,
    this.completed = false,
  });

  int get length => end - start + 1;
  int get currentPosition => start + downloaded;
}

class MultiThreadDownloader {
  final Dio _dio;
  final int threadCount;
  final int minChunkSize;

  bool _cancelled = false;
  bool _paused = false;
  final List<CancelToken> _cancelTokens = [];

  static const String defaultUserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/87.0.4280.88 Safari/537.36 Edg/87.0.664.57';

  MultiThreadDownloader({
    Dio? dio,
    this.threadCount = 8,
    this.minChunkSize = 1024 * 1024, // 1MB
  }) : _dio = dio ?? Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(hours: 2),
  ));

  // 检测是否是 115 链接
  bool _is115Link(String url) {
    return url.contains('115cdn.net') || url.contains('cdnfhnfile') || url.contains('115.com');
  }

  Future<bool> _supportsRangeRequest(String url, Map<String, String>? headers) async {
    // 115 链接支持 Range 请求，但不支持 HEAD 请求
    if (_is115Link(url)) {
      debugPrint('[MultiThreadDownloader] 115 link detected, assuming range support');
      return true;
    }
    try {
      final response = await _dio.head(
        url,
        options: Options(headers: headers),
      );
      final acceptRanges = response.headers.value('accept-ranges');
      final contentLength = response.headers.value('content-length');
      return acceptRanges == 'bytes' && contentLength != null;
    } catch (e) {
      debugPrint('[MultiThreadDownloader] HEAD request failed: $e');
      return false;
    }
  }

  Future<int?> _getFileSize(String url, Map<String, String>? headers) async {
    // 115 链接不支持 HEAD 请求，使用 Range: bytes=0-0 获取大小
    if (_is115Link(url)) {
      return await _getFileSizeViaRange(url, headers);
    }
    try {
      final response = await _dio.head(
        url,
        options: Options(headers: headers),
      );
      final contentLength = response.headers.value('content-length');
      if (contentLength != null) {
        return int.tryParse(contentLength);
      }
    } catch (e) {
      debugPrint('[MultiThreadDownloader] Failed to get file size: $e');
    }
    return null;
  }

  Future<int?> _getFileSizeViaRange(String url, Map<String, String>? headers) async {
    try {
      final response = await _dio.get(
        url,
        options: Options(
          headers: {
            ...?headers,
            'Range': 'bytes=0-0',
          },
          validateStatus: (status) => status == 200 || status == 206,
          responseType: ResponseType.stream,
        ),
      );

      final contentRange = response.headers.value('content-range');
      if (contentRange != null) {
        final match = RegExp(r'/(\d+)').firstMatch(contentRange);
        if (match != null) {
          final size = int.tryParse(match.group(1)!);
          debugPrint('[MultiThreadDownloader] Got file size via Range: $size');
          await (response.data as ResponseBody).stream.drain();
          return size;
        }
      }
      await (response.data as ResponseBody).stream.drain();
    } catch (e) {
      debugPrint('[MultiThreadDownloader] Failed to get file size via Range: $e');
    }
    return null;
  }

  Future<void> download({
    required String url,
    required String savePath,
    Map<String, String>? headers,
    void Function(DownloadProgress)? onProgress,
    void Function()? onComplete,
    void Function(String error)? onError,
    int? existingBytes,
  }) async {
    _cancelled = false;
    _paused = false;
    _cancelTokens.clear();

    // 确保有 User-Agent
    final effectiveHeaders = <String, String>{
      'User-Agent': defaultUserAgent,
      ...?headers,
    };

    try {
      final file = File(savePath);
      final parentDir = file.parent;
      if (!await parentDir.exists()) {
        await parentDir.create(recursive: true);
      }

      final fileSize = await _getFileSize(url, effectiveHeaders);
      final supportsRange = await _supportsRangeRequest(url, effectiveHeaders);
      final is115 = _is115Link(url);

      debugPrint('[MultiThreadDownloader] File size: $fileSize, Supports range: $supportsRange, Threads: $threadCount, is115: $is115');

      if (fileSize == null || !supportsRange || fileSize < minChunkSize * 2) {
        await _singleThreadDownload(
          url: url,
          savePath: savePath,
          headers: effectiveHeaders,
          fileSize: fileSize ?? 0,
          onProgress: onProgress,
          onComplete: onComplete,
          onError: onError,
        );
        return;
      }

      await _multiThreadDownload(
        url: url,
        savePath: savePath,
        headers: effectiveHeaders,
        fileSize: fileSize,
        is115: is115,
        onProgress: onProgress,
        onComplete: onComplete,
        onError: onError,
        existingBytes: existingBytes,
      );
    } catch (e) {
      if (!_cancelled) {
        onError?.call(e.toString());
      }
    }
  }

  Future<void> _singleThreadDownload({
    required String url,
    required String savePath,
    Map<String, String>? headers,
    required int fileSize,
    void Function(DownloadProgress)? onProgress,
    void Function()? onComplete,
    void Function(String error)? onError,
  }) async {
    debugPrint('[MultiThreadDownloader] Using single thread download');

    final cancelToken = CancelToken();
    _cancelTokens.add(cancelToken);

    final file = File(savePath);
    int downloadedBytes = 0;
    if (await file.exists()) {
      downloadedBytes = await file.length();
    }

    final sink = file.openWrite(mode: downloadedBytes > 0 ? FileMode.append : FileMode.write);

    try {
      final options = Options(
        headers: {
          ...?headers,
          if (downloadedBytes > 0) 'Range': 'bytes=$downloadedBytes-',
        },
        responseType: ResponseType.stream,
      );

      final response = await _dio.get<ResponseBody>(
        url,
        options: options,
        cancelToken: cancelToken,
      );

      int totalBytes = fileSize;
      if (totalBytes == 0) {
        final contentLength = response.headers.value('content-length');
        if (contentLength != null) {
          totalBytes = int.parse(contentLength) + downloadedBytes;
        }
      }

      var lastUpdateTime = DateTime.now();
      var lastBytes = downloadedBytes;
      double smoothedSpeed = 0;
      const double alpha = 0.3;

      await for (final chunk in response.data!.stream) {
        if (_cancelled) break;
        while (_paused && !_cancelled) {
          await Future.delayed(const Duration(milliseconds: 100));
        }
        if (_cancelled) break;

        sink.add(chunk);
        downloadedBytes += chunk.length;

        final now = DateTime.now();
        final elapsed = now.difference(lastUpdateTime).inMilliseconds;
        if (elapsed >= 500) {
          final bytesDiff = downloadedBytes - lastBytes;
          final instantSpeed = bytesDiff / (elapsed / 1000);
          smoothedSpeed = smoothedSpeed == 0 ? instantSpeed : alpha * instantSpeed + (1 - alpha) * smoothedSpeed;
          lastUpdateTime = now;
          lastBytes = downloadedBytes;

          onProgress?.call(DownloadProgress(
            downloadedBytes: downloadedBytes,
            totalBytes: totalBytes,
            speed: smoothedSpeed,
            activeThreads: 1,
          ));
        }
      }

      await sink.flush();
      await sink.close();

      if (!_cancelled) {
        onComplete?.call();
      }
    } catch (e) {
      await sink.close();
      if (e is DioException && e.type == DioExceptionType.cancel) {
        return;
      }
      rethrow;
    }
  }

  Future<void> _multiThreadDownload({
    required String url,
    required String savePath,
    Map<String, String>? headers,
    required int fileSize,
    bool is115 = false,
    void Function(DownloadProgress)? onProgress,
    void Function()? onComplete,
    void Function(String error)? onError,
    int? existingBytes,
  }) async {
    // 115 链接有时效性，必须确保所有分片同时开始下载
    // 使用较少的分片数，确保所有连接在链接过期前建立
    final effectiveThreadCount = is115 ? threadCount : threadCount;
    debugPrint('[MultiThreadDownloader] Using $effectiveThreadCount threads for download (is115: $is115)');

    final tempDir = '$savePath.parts';
    final tempDirFile = Directory(tempDir);
    if (!await tempDirFile.exists()) {
      await tempDirFile.create(recursive: true);
    }

    // 对于 115 链接，分片数 = 线程数，确保所有分片同时开始
    // 对于其他链接，可以有更多分片
    final chunkCount = is115 ? effectiveThreadCount : max(effectiveThreadCount, (fileSize / minChunkSize).ceil());
    final chunkSize = (fileSize / chunkCount).ceil();
    final chunks = <DownloadChunk>[];

    int offset = 0;
    int index = 0;
    while (offset < fileSize) {
      final end = min(offset + chunkSize - 1, fileSize - 1);
      chunks.add(DownloadChunk(index: index, start: offset, end: end));
      offset = end + 1;
      index++;
    }

    debugPrint('[MultiThreadDownloader] Created ${chunks.length} chunks');

    for (final chunk in chunks) {
      final partFile = File('$tempDir/part_${chunk.index}');
      if (await partFile.exists()) {
        final existingSize = await partFile.length();
        if (existingSize == chunk.length) {
          chunk.completed = true;
          chunk.downloaded = existingSize;
        } else if (existingSize > 0 && existingSize < chunk.length) {
          chunk.downloaded = existingSize;
        }
      }
    }

    final downloadedBytesMap = <int, int>{};
    for (final chunk in chunks) {
      downloadedBytesMap[chunk.index] = chunk.downloaded;
    }

    var lastUpdateTime = DateTime.now();
    var lastTotalBytes = downloadedBytesMap.values.fold(0, (a, b) => a + b);
    double smoothedSpeed = 0;
    const double alpha = 0.3;
    int activeThreads = 0;

    void updateProgress() {
      final totalDownloaded = downloadedBytesMap.values.fold(0, (a, b) => a + b);
      final now = DateTime.now();
      final elapsed = now.difference(lastUpdateTime).inMilliseconds;

      if (elapsed >= 500) {
        final bytesDiff = totalDownloaded - lastTotalBytes;
        final instantSpeed = bytesDiff / (elapsed / 1000);
        smoothedSpeed = smoothedSpeed == 0 ? instantSpeed : alpha * instantSpeed + (1 - alpha) * smoothedSpeed;
        lastUpdateTime = now;
        lastTotalBytes = totalDownloaded;

        onProgress?.call(DownloadProgress(
          downloadedBytes: totalDownloaded,
          totalBytes: fileSize,
          speed: smoothedSpeed,
          activeThreads: activeThreads,
        ));
      }
    }

    final progressTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      updateProgress();
    });

    try {
      final pendingChunks = chunks.where((c) => !c.completed).toList();
      final futures = <Future>[];

      // 对于 115 链接，所有分片同时开始下载（不使用信号量排队）
      // 这样所有 TCP 连接在链接过期前就能建立
      if (is115) {
        debugPrint('[MultiThreadDownloader] 115 link: starting all ${pendingChunks.length} chunks simultaneously');
        for (final chunk in pendingChunks) {
          if (_cancelled) break;
          activeThreads++;
          futures.add(_downloadChunk(
            url: url,
            headers: headers,
            chunk: chunk,
            tempDir: tempDir,
            onProgress: (bytes) {
              downloadedBytesMap[chunk.index] = bytes;
            },
          ).whenComplete(() => activeThreads--));
        }
      } else {
        // 非 115 链接使用信号量控制并发
        final semaphore = _Semaphore(threadCount);
        for (final chunk in pendingChunks) {
          if (_cancelled) break;

          futures.add(() async {
            await semaphore.acquire();
            activeThreads++;
            try {
              await _downloadChunk(
                url: url,
                headers: headers,
                chunk: chunk,
                tempDir: tempDir,
                onProgress: (bytes) {
                  downloadedBytesMap[chunk.index] = bytes;
                },
              );
            } finally {
              activeThreads--;
              semaphore.release();
            }
          }());
        }
      }

      await Future.wait(futures);
      progressTimer.cancel();

      if (_cancelled) {
        return;
      }

      final allCompleted = chunks.every((c) => c.completed);
      if (!allCompleted) {
        onError?.call('部分分片下载失败');
        return;
      }

      debugPrint('[MultiThreadDownloader] All chunks downloaded, merging...');

      final outputFile = File(savePath);
      final outputSink = outputFile.openWrite();

      for (final chunk in chunks) {
        final partFile = File('$tempDir/part_${chunk.index}');
        final partData = await partFile.readAsBytes();
        outputSink.add(partData);
      }

      await outputSink.flush();
      await outputSink.close();

      await tempDirFile.delete(recursive: true);

      debugPrint('[MultiThreadDownloader] Download completed');
      onComplete?.call();
    } catch (e) {
      progressTimer.cancel();
      if (!_cancelled) {
        onError?.call(e.toString());
      }
    }
  }

  Future<void> _downloadChunk({
    required String url,
    Map<String, String>? headers,
    required DownloadChunk chunk,
    required String tempDir,
    required void Function(int bytes) onProgress,
  }) async {
    if (_cancelled || chunk.completed) return;

    final cancelToken = CancelToken();
    _cancelTokens.add(cancelToken);

    final partFile = File('$tempDir/part_${chunk.index}');
    final startPosition = chunk.start + chunk.downloaded;
    final endPosition = chunk.end;

    if (startPosition > endPosition) {
      chunk.completed = true;
      return;
    }

    debugPrint('[MultiThreadDownloader] Downloading chunk ${chunk.index}: $startPosition-$endPosition');

    try {
      final response = await _dio.get<ResponseBody>(
        url,
        options: Options(
          headers: {
            ...?headers,
            'Range': 'bytes=$startPosition-$endPosition',
          },
          responseType: ResponseType.stream,
        ),
        cancelToken: cancelToken,
      );

      final sink = partFile.openWrite(mode: chunk.downloaded > 0 ? FileMode.append : FileMode.write);

      await for (final data in response.data!.stream) {
        if (_cancelled) break;
        while (_paused && !_cancelled) {
          await Future.delayed(const Duration(milliseconds: 100));
        }
        if (_cancelled) break;

        sink.add(data);
        chunk.downloaded += data.length;
        onProgress(chunk.downloaded);
      }

      await sink.flush();
      await sink.close();

      if (!_cancelled && chunk.downloaded >= chunk.length) {
        chunk.completed = true;
        debugPrint('[MultiThreadDownloader] Chunk ${chunk.index} completed');
      }
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        return;
      }
      debugPrint('[MultiThreadDownloader] Chunk ${chunk.index} error: $e');
      rethrow;
    }
  }

  void pause() {
    _paused = true;
  }

  void resume() {
    _paused = false;
  }

  void cancel() {
    _cancelled = true;
    _paused = false;
    for (final token in _cancelTokens) {
      token.cancel('cancelled');
    }
    _cancelTokens.clear();
  }

  bool get isPaused => _paused;
  bool get isCancelled => _cancelled;
}

class _Semaphore {
  final int maxCount;
  int _currentCount = 0;
  final _waitQueue = <Completer<void>>[];

  _Semaphore(this.maxCount);

  Future<void> acquire() async {
    if (_currentCount < maxCount) {
      _currentCount++;
      return;
    }
    final completer = Completer<void>();
    _waitQueue.add(completer);
    await completer.future;
  }

  void release() {
    if (_waitQueue.isNotEmpty) {
      final completer = _waitQueue.removeAt(0);
      completer.complete();
    } else {
      _currentCount--;
    }
  }
}
