import 'dart:convert';

/// 存储源模型
class Storage {
  final int id;
  final String name;
  final String type;
  final Map<String, String>? settings;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Storage({
    required this.id,
    required this.name,
    required this.type,
    this.settings,
    this.createdAt,
    this.updatedAt,
  });

  factory Storage.fromJson(Map<String, dynamic> json) {
    Map<String, String>? parsedSettings;
    final settingsValue = json['settings'];
    if (settingsValue is Map<String, dynamic>) {
      parsedSettings = settingsValue.cast<String, String>();
    } else if (settingsValue is String && settingsValue.isNotEmpty) {
      try {
        final decoded = jsonDecode(settingsValue);
        if (decoded is Map<String, dynamic>) {
          parsedSettings = decoded.cast<String, String>();
        }
      } catch (_) {
        // Ignore JSON parse errors
      }
    }

    return Storage(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      type: json['type'] as String? ?? '',
      settings: parsedSettings,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type,
        'settings': settings,
        'created_at': createdAt?.toIso8601String(),
        'updated_at': updatedAt?.toIso8601String(),
      };

  /// 获取类型显示名称
  String get typeDisplayName {
    switch (type.toLowerCase()) {
      case 'webdav':
        return 'WebDAV';
      case 'local':
        return '本地存储';
      default:
        return type;
    }
  }
}

/// 扫描进度模型
class ScanProgress {
  final int taskId;
  final int storageId;
  final String status;
  final int totalFiles;
  final int scannedFiles;
  final double progress;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final String? error;

  ScanProgress({
    required this.taskId,
    required this.storageId,
    required this.status,
    required this.totalFiles,
    required this.scannedFiles,
    required this.progress,
    this.startedAt,
    this.finishedAt,
    this.error,
  });

  factory ScanProgress.fromJson(Map<String, dynamic> json) {
    return ScanProgress(
      taskId: json['task_id'] as int? ?? 0,
      storageId: json['storage_id'] as int? ?? 0,
      status: json['status'] as String? ?? '',
      totalFiles: json['total_files'] as int? ?? 0,
      scannedFiles: json['scanned_files'] as int? ?? 0,
      progress: (json['progress'] as num?)?.toDouble() ?? 0.0,
      startedAt: json['started_at'] != null
          ? DateTime.tryParse(json['started_at'] as String)
          : null,
      finishedAt: json['finished_at'] != null
          ? DateTime.tryParse(json['finished_at'] as String)
          : null,
      error: json['error'] as String?,
    );
  }

  /// 是否正在运行
  bool get isRunning => status == 'running';

  /// 是否已完成
  bool get isCompleted => status == 'completed';

  /// 是否失败
  bool get isFailed => status == 'failed';

  /// 获取状态显示文本
  String get statusText {
    switch (status) {
      case 'running':
        return '扫描中';
      case 'completed':
        return '已完成';
      case 'failed':
        return '失败';
      case 'pending':
        return '等待中';
      default:
        return status;
    }
  }
}

/// 文件信息模型（用于浏览目录）
class FileInfo {
  final String name;
  final String path;
  final bool isDir;
  final int? size;
  final DateTime? modTime;

  FileInfo({
    required this.name,
    required this.path,
    required this.isDir,
    this.size,
    this.modTime,
  });

  factory FileInfo.fromJson(Map<String, dynamic> json) {
    return FileInfo(
      name: json['name'] as String? ?? '',
      path: json['path'] as String? ?? '',
      isDir: json['is_dir'] as bool? ?? false,
      size: json['size'] as int?,
      modTime: json['mod_time'] != null
          ? DateTime.tryParse(json['mod_time'] as String)
          : null,
    );
  }

  /// 格式化文件大小
  String get formattedSize {
    if (size == null || isDir) return '';
    final gb = size! / (1024 * 1024 * 1024);
    if (gb >= 1) {
      return '${gb.toStringAsFixed(2)} GB';
    }
    final mb = size! / (1024 * 1024);
    if (mb >= 1) {
      return '${mb.toStringAsFixed(2)} MB';
    }
    final kb = size! / 1024;
    return '${kb.toStringAsFixed(2)} KB';
  }
}
