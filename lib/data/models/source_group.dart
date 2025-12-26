/// 播放源分组模型（按文件夹聚合）
class SourceGroup {
  final String folderPath;
  final int fileCount;
  final int totalSize;
  final String? resolution;
  final String? storageName;
  final bool isPrimary;

  SourceGroup({
    required this.folderPath,
    required this.fileCount,
    required this.totalSize,
    this.resolution,
    this.storageName,
    this.isPrimary = false,
  });

  factory SourceGroup.fromJson(Map<String, dynamic> json) {
    return SourceGroup(
      folderPath: json['folder_path'] as String? ?? '',
      fileCount: (json['file_count'] as num?)?.toInt() ?? 0,
      totalSize: (json['total_size'] as num?)?.toInt() ?? 0,
      resolution: json['resolution'] as String?,
      storageName: json['storage_name'] as String?,
      isPrimary: json['is_primary'] as bool? ?? false,
    );
  }

  /// 格式化文件大小
  String get formattedSize {
    if (totalSize < 1024) return '$totalSize B';
    if (totalSize < 1024 * 1024) return '${(totalSize / 1024).toStringAsFixed(1)} KB';
    if (totalSize < 1024 * 1024 * 1024) {
      return '${(totalSize / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(totalSize / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  /// 显示标签（优先 resolution，否则从路径提取）
  String get displayLabel {
    if (resolution != null && resolution!.isNotEmpty) return resolution!;
    final parts = folderPath.split('/');
    return parts.isNotEmpty ? parts.last : folderPath;
  }
}
