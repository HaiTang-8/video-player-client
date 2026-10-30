import 'stream_link.dart';

/// 播放信息模型
class StreamInfo {
  final String url;
  final String? mimeType;
  final int? fileSize;
  final String? fileName;
  final int? storageId;
  final String? filePath;

  /// 剧集的播放源 ID，经 /links/source/:id 获取直链时使用
  final int? sourceId;
  final StreamDelivery delivery;

  StreamInfo({
    required this.url,
    this.mimeType,
    this.fileSize,
    this.fileName,
    this.storageId,
    this.filePath,
    this.sourceId,
    this.delivery = StreamDelivery.stream,
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
      sourceId: json['source_id'] as int?,
      delivery: StreamDelivery.fromJson(json['delivery']),
    );
  }

  Map<String, dynamic> toJson() => {
        'url': url,
        'mime_type': mimeType,
        'file_size': fileSize,
        'file_name': fileName,
        'storage_id': storageId,
        'file_path': filePath,
        'source_id': sourceId,
        'delivery':
            delivery == StreamDelivery.directLink ? 'direct_link' : 'stream',
      };
}
