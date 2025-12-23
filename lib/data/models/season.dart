import 'dart:convert';
import 'episode.dart';
import 'cast_member.dart';
import 'crew_member.dart';

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

  /// 本季演员详情（含头像/角色等）
  final List<CastMember>? castDetail;

  /// 本季职员详情（职位/头像等）
  final List<CrewMember>? crewDetail;
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
    this.castDetail,
    this.crewDetail,
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
      airDate:
          json['air_date'] != null
              ? DateTime.tryParse(json['air_date'].toString())
              : null,
      episodeCount: (json['episode_count'] as num?)?.toInt(),
      castDetail: _parseCastDetail(json['cast_detail']),
      crewDetail: _parseCrewDetail(json['crew_detail']),
      episodes:
          (json['episodes'] as List<dynamic>?)
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
    'cast_detail': castDetail?.map((e) => e.toJson()).toList(),
    'crew_detail': crewDetail?.map((e) => e.toJson()).toList(),
    'episodes': episodes?.map((e) => e.toJson()).toList(),
  };

  static List<CastMember>? _parseCastDetail(dynamic value) {
    if (value == null) return null;
    dynamic decoded = value;
    if (value is String && value.isNotEmpty) {
      try {
        decoded = jsonDecode(value);
      } catch (_) {
        return null;
      }
    }

    if (decoded is List) {
      final out = <CastMember>[];
      for (final item in decoded) {
        if (item is Map) {
          out.add(CastMember.fromJson(Map<String, dynamic>.from(item)));
          continue;
        }
        final name = item?.toString() ?? '';
        if (name.isNotEmpty) {
          out.add(CastMember(name: name));
        }
      }
      return out.isEmpty ? null : out;
    }

    return null;
  }

  static List<CrewMember>? _parseCrewDetail(dynamic value) {
    if (value == null) return null;
    dynamic decoded = value;
    if (value is String && value.isNotEmpty) {
      try {
        decoded = jsonDecode(value);
      } catch (_) {
        return null;
      }
    }

    if (decoded is List) {
      final out = <CrewMember>[];
      for (final item in decoded) {
        if (item is Map) {
          out.add(CrewMember.fromJson(Map<String, dynamic>.from(item)));
          continue;
        }
        final name = item?.toString() ?? '';
        if (name.isNotEmpty) {
          out.add(CrewMember(name: name));
        }
      }
      return out.isEmpty ? null : out;
    }

    return null;
  }

  /// 显示名称
  String get displayName {
    if (seasonNumber == 0) {
      return '特别篇';
    }
    return name ?? '第 $seasonNumber 季';
  }
}
