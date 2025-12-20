/// 播放信息模型
class StreamInfo {
  final String url;
  final String? mimeType;
  final int? fileSize;
  final String? fileName;

  StreamInfo({
    required this.url,
    this.mimeType,
    this.fileSize,
    this.fileName,
  });

  factory StreamInfo.fromJson(Map<String, dynamic> json) {
    return StreamInfo(
      url: json['url'] as String? ?? '',
      mimeType: json['mime_type'] as String?,
      fileSize: json['file_size'] as int?,
      fileName: json['file_name'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'url': url,
        'mime_type': mimeType,
        'file_size': fileSize,
        'file_name': fileName,
      };
}
