class MediaImageInfo {
  final String filePath;
  final String url;
  final double aspectRatio;
  final int width;
  final int height;
  final double voteAverage;
  final int voteCount;
  final String? language;

  const MediaImageInfo({
    required this.filePath,
    required this.url,
    required this.aspectRatio,
    required this.width,
    required this.height,
    required this.voteAverage,
    required this.voteCount,
    this.language,
  });

  factory MediaImageInfo.fromJson(Map<String, dynamic> json) {
    return MediaImageInfo(
      filePath: json['file_path'] as String? ?? '',
      url: json['url'] as String? ?? '',
      aspectRatio: (json['aspect_ratio'] as num?)?.toDouble() ?? 0.0,
      width: json['width'] as int? ?? 0,
      height: json['height'] as int? ?? 0,
      voteAverage: (json['vote_average'] as num?)?.toDouble() ?? 0.0,
      voteCount: json['vote_count'] as int? ?? 0,
      language: json['language'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'file_path': filePath,
      'url': url,
      'aspect_ratio': aspectRatio,
      'width': width,
      'height': height,
      'vote_average': voteAverage,
      'vote_count': voteCount,
      if (language != null) 'language': language,
    };
  }
}

class MediaImages {
  final List<MediaImageInfo> posters;
  final List<MediaImageInfo> backdrops;

  const MediaImages({
    required this.posters,
    required this.backdrops,
  });

  factory MediaImages.fromJson(Map<String, dynamic> json) {
    return MediaImages(
      posters: (json['posters'] as List<dynamic>?)
              ?.map((e) => MediaImageInfo.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      backdrops: (json['backdrops'] as List<dynamic>?)
              ?.map((e) => MediaImageInfo.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'posters': posters.map((e) => e.toJson()).toList(),
      'backdrops': backdrops.map((e) => e.toJson()).toList(),
    };
  }
}
