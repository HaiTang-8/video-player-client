class SubtitleInfo {
  final String name;
  final String path;
  final String url;
  final String? language;
  final int score;

  /// 随下载缓存到本机的字幕文件；有值时直接读取，不再请求服务器
  final String? localPath;

  SubtitleInfo({
    required this.name,
    required this.path,
    required this.url,
    this.language,
    required this.score,
    this.localPath,
  });

  factory SubtitleInfo.fromJson(Map<String, dynamic> json) {
    return SubtitleInfo(
      name: json['name'] as String? ?? '',
      path: json['path'] as String? ?? '',
      url: json['url'] as String? ?? '',
      language: json['language'] as String?,
      score: json['score'] as int? ?? 0,
      localPath: json['local_path'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'path': path,
    'url': url,
    'language': language,
    'score': score,
    'local_path': localPath,
  };

  SubtitleInfo withLocalPath(String localPath) => SubtitleInfo(
    name: name,
    path: path,
    url: url,
    language: language,
    score: score,
    localPath: localPath,
  );

  String get displayName {
    if (language != null && language!.isNotEmpty) {
      return '$name ($language)';
    }
    return name;
  }
}
