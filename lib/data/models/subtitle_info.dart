class SubtitleInfo {
  final String name;
  final String path;
  final String url;
  final String? language;
  final int score;

  SubtitleInfo({
    required this.name,
    required this.path,
    required this.url,
    this.language,
    required this.score,
  });

  factory SubtitleInfo.fromJson(Map<String, dynamic> json) {
    return SubtitleInfo(
      name: json['name'] as String? ?? '',
      path: json['path'] as String? ?? '',
      url: json['url'] as String? ?? '',
      language: json['language'] as String?,
      score: json['score'] as int? ?? 0,
    );
  }

  String get displayName {
    if (language != null && language!.isNotEmpty) {
      return '$name ($language)';
    }
    return name;
  }
}
