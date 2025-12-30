/// 播放信息模型
class StreamInfo {
  final String url;
  final String? mimeType;
  final int? fileSize;
  final String? fileName;
  final int? storageId;
  final String? filePath;

  StreamInfo({
    required this.url,
    this.mimeType,
    this.fileSize,
    this.fileName,
    this.storageId,
    this.filePath,
  });

  factory StreamInfo.fromJson(Map<String, dynamic> json) {
    return StreamInfo(
      // 后端可能返回：
      // - safe_url：推荐使用，避免复杂路径编码导致的播放失败
      // - url：旧版路径模式
      url: json['safe_url'] as String? ??
          json['url'] as String? ??
          json['file_path'] as String? ??
          '',
      mimeType: json['mime_type'] as String?,
      fileSize: json['file_size'] as int?,
      fileName: json['file_name'] as String?,
      storageId: json['storage_id'] as int?,
      filePath: json['file_path'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'url': url,
        'mime_type': mimeType,
        'file_size': fileSize,
        'file_name': fileName,
        'storage_id': storageId,
        'file_path': filePath,
      };
}
