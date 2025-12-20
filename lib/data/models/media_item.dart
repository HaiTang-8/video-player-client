/// 媒体类型
enum MediaType {
  movie,
  tvshow,
}

/// 海报墙项目（电影或剧集的统一展示）
class MediaItem {
  final int id;
  final MediaType type;
  final String title;
  final String? originalTitle;
  final String? posterPath;
  final String? backdropPath;
  final String? overview;
  final double? rating;
  final int? year;
  final DateTime? releaseDate;
  final int? numberOfSeasons; // 剧集季数，电影为 null

  MediaItem({
    required this.id,
    required this.type,
    required this.title,
    this.originalTitle,
    this.posterPath,
    this.backdropPath,
    this.overview,
    this.rating,
    this.year,
    this.releaseDate,
    this.numberOfSeasons,
  });

  factory MediaItem.fromJson(Map<String, dynamic> json) {
    // 兼容两种格式：
    // 1. 海报墙格式: media_type, media_id
    // 2. 标准格式: type, id
    final typeStr = json['media_type'] as String? ?? json['type'] as String? ?? 'movie';
    return MediaItem(
      id: (json['media_id'] as num?)?.toInt() ?? (json['id'] as num?)?.toInt() ?? 0,
      type: typeStr == 'tv' || typeStr == 'tvshow' ? MediaType.tvshow : MediaType.movie,
      title: json['title'] as String? ?? json['name'] as String? ?? '',
      originalTitle: json['original_title'] as String? ?? json['original_name'] as String?,
      posterPath: json['poster_path'] as String?,
      backdropPath: json['backdrop_path'] as String?,
      overview: json['overview'] as String?,
      rating: (json['vote_average'] as num?)?.toDouble(),
      year: (json['year'] as num?)?.toInt(),
      releaseDate: json['release_date'] != null
          ? DateTime.tryParse(json['release_date'].toString())
          : json['first_air_date'] != null
              ? DateTime.tryParse(json['first_air_date'].toString())
              : null,
      numberOfSeasons: (json['number_of_seasons'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type == MediaType.tvshow ? 'tvshow' : 'movie',
        'title': title,
        'original_title': originalTitle,
        'poster_path': posterPath,
        'backdrop_path': backdropPath,
        'overview': overview,
        'vote_average': rating,
        'year': year,
        'release_date': releaseDate?.toIso8601String(),
        'number_of_seasons': numberOfSeasons,
      };
}
