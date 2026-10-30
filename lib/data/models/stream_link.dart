/// 获取播放地址的方式：direct_link 经 /links 拿直链与请求头，客户端直连网盘；stream 走服务端 /stream
enum StreamDelivery {
  stream,
  directLink;

  static StreamDelivery fromJson(Object? value) =>
      value == 'direct_link' ? directLink : stream;
}

/// 直链类型：file 可按 Range 读取的原文件，hls 播放列表
enum StreamLinkKind {
  file,
  hls;

  static StreamLinkKind fromJson(Object? value) => value == 'hls' ? hls : file;
}

/// 播放 / 下载直链；[headers] 是访问直链必须携带的请求头，优先级高于所有默认请求头
class StreamLink {
  const StreamLink({
    required this.url,
    this.delivery = StreamDelivery.directLink,
    this.kind = StreamLinkKind.file,
    this.variant = originalVariant,
    this.headers = const {},
    this.expiresAt,
    this.maxConnections,
  });

  static const originalVariant = 'original';

  final String url;
  final StreamDelivery delivery;
  final StreamLinkKind kind;
  final String variant;
  final Map<String, String> headers;
  final DateTime? expiresAt;
  final int? maxConnections;

  bool get isDirect => delivery == StreamDelivery.directLink;

  factory StreamLink.fromJson(Map<String, dynamic> json) {
    final headers = json['headers'];
    final expires = json['expires_at'];
    return StreamLink(
      url: json['url'] as String? ?? '',
      delivery: StreamDelivery.fromJson(json['delivery']),
      kind: StreamLinkKind.fromJson(json['kind']),
      variant: json['variant'] as String? ?? originalVariant,
      headers:
          headers is Map
              ? headers.map((k, v) => MapEntry(k.toString(), v.toString()))
              : const {},
      expiresAt: expires is String ? DateTime.tryParse(expires) : null,
      maxConnections: (json['max_connections'] as num?)?.toInt(),
    );
  }
}

/// 网盘文件的可选版本（原画 / 各档转码），由 /links/*/variants 返回
class LinkVariant {
  const LinkVariant({
    required this.id,
    required this.label,
    this.kind = StreamLinkKind.file,
    this.original = false,
  });

  final String id;
  final String label;
  final StreamLinkKind kind;
  final bool original;

  factory LinkVariant.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String? ?? StreamLink.originalVariant;
    return LinkVariant(
      id: id,
      label: json['label'] as String? ?? id,
      kind: StreamLinkKind.fromJson(json['kind']),
      original: json['original'] as bool? ?? false,
    );
  }
}
