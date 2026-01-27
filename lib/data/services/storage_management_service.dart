import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'download_service.dart';

class StorageCategory {
  final String id;
  final String name;
  final String description;
  final int size;
  final bool canClear;

  const StorageCategory({
    required this.id,
    required this.name,
    required this.description,
    required this.size,
    this.canClear = true,
  });

  StorageCategory copyWith({int? size}) {
    return StorageCategory(
      id: id,
      name: name,
      description: description,
      size: size ?? this.size,
      canClear: canClear,
    );
  }
}

class StorageManagementService {
  static StorageManagementService? _instance;
  static StorageManagementService get instance =>
      _instance ??= StorageManagementService._();

  StorageManagementService._();

  Future<List<StorageCategory>> getStorageUsage() async {
    final categories = <StorageCategory>[];

    // 下载文件
    final downloadSize = await _getDownloadSize();
    categories.add(StorageCategory(
      id: 'downloads',
      name: '下载文件',
      description: '已下载的视频文件',
      size: downloadSize,
    ));

    // 图片缓存
    final imageCacheSize = await _getImageCacheSize();
    categories.add(StorageCategory(
      id: 'image_cache',
      name: '图片缓存',
      description: '海报、剧照等图片缓存',
      size: imageCacheSize,
    ));

    // 日志文件
    final logSize = await _getLogSize();
    categories.add(StorageCategory(
      id: 'logs',
      name: '日志文件',
      description: '应用运行日志',
      size: logSize,
    ));

    return categories;
  }

  Future<int> getTotalUsage() async {
    final categories = await getStorageUsage();
    return categories.fold<int>(0, (sum, cat) => sum + cat.size);
  }

  Future<int> _getDownloadSize() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final downloadDir = Directory('${dir.path}/downloads');
      if (!await downloadDir.exists()) return 0;
      return await _calculateDirectorySize(downloadDir);
    } catch (_) {
      return 0;
    }
  }

  Future<int> _getImageCacheSize() async {
    try {
      final cacheDir = await getTemporaryDirectory();
      final imageCacheDir = Directory('${cacheDir.path}/libCachedImageData');
      if (!await imageCacheDir.exists()) return 0;
      return await _calculateDirectorySize(imageCacheDir);
    } catch (_) {
      return 0;
    }
  }

  Future<int> _getLogSize() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final logDir = Directory('${dir.path}/logs');
      if (!await logDir.exists()) return 0;
      return await _calculateDirectorySize(logDir);
    } catch (_) {
      return 0;
    }
  }

  Future<int> _calculateDirectorySize(Directory dir) async {
    int size = 0;
    try {
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File) {
          size += await entity.length();
        }
      }
    } catch (_) {}
    return size;
  }

  Future<void> clearCategory(String categoryId) async {
    switch (categoryId) {
      case 'downloads':
        await _clearDownloads();
        break;
      case 'image_cache':
        await _clearImageCache();
        break;
      case 'logs':
        await _clearLogs();
        break;
    }
  }

  Future<void> clearAll() async {
    await _clearImageCache();
    await _clearLogs();
  }

  Future<void> _clearDownloads() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final downloadDir = Directory('${dir.path}/downloads');
      if (await downloadDir.exists()) {
        await downloadDir.delete(recursive: true);
      }
      // Keep persistent records consistent with the filesystem.
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(DownloadService.tasksKey);
    } catch (_) {}
  }

  Future<void> _clearImageCache() async {
    try {
      final cacheDir = await getTemporaryDirectory();
      final imageCacheDir = Directory('${cacheDir.path}/libCachedImageData');
      if (await imageCacheDir.exists()) {
        await imageCacheDir.delete(recursive: true);
      }
    } catch (_) {}
  }

  Future<void> _clearLogs() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final logDir = Directory('${dir.path}/logs');
      if (await logDir.exists()) {
        await for (final file in logDir.list()) {
          if (file is File) {
            await file.delete();
          }
        }
      }
    } catch (_) {}
  }

  String formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
