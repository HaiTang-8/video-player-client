import 'episode.dart';

/// 季模型
class Season {
  final int id;
  final int tvShowId;
  final int seasonNumber;
  final String? name;
  final String? overview;
  final String? posterPath;
  final DateTime? airDate;
  final int? episodeCount;
  final List<Episode>? episodes;

  Season({
    required this.id,
    required this.tvShowId,
    required this.seasonNumber,
    this.name,
    this.overview,
    this.posterPath,
    this.airDate,
    this.episodeCount,
    this.episodes,
  });

  factory Season.fromJson(Map<String, dynamic> json) {
    return Season(
      id: (json['id'] as num?)?.toInt() ?? 0,
      tvShowId: (json['tv_show_id'] as num?)?.toInt() ?? 0,
      seasonNumber: (json['season_number'] as num?)?.toInt() ?? 0,
      name: json['name'] as String?,
      overview: json['overview'] as String?,
      posterPath: json['poster_path'] as String?,
      airDate: json['air_date'] != null
          ? DateTime.tryParse(json['air_date'].toString())
          : null,
      episodeCount: (json['episode_count'] as num?)?.toInt(),
      episodes: (json['episodes'] as List<dynamic>?)
          ?.map((e) => Episode.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'tv_show_id': tvShowId,
        'season_number': seasonNumber,
        'name': name,
        'overview': overview,
        'poster_path': posterPath,
        'air_date': airDate?.toIso8601String(),
        'episode_count': episodeCount,
        'episodes': episodes?.map((e) => e.toJson()).toList(),
      };

  /// 显示名称
  String get displayName {
    if (seasonNumber == 0) {
      return '特别篇';
    }
    return name ?? '第 $seasonNumber 季';
  }
}
