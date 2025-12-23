import 'dart:convert';
import 'season.dart';
import 'cast_member.dart';

/// 剧集模型
class TvShow {
  final int id;
  final String name;
  final String? originalName;
  final String? overview;
  final String? posterPath;
  final String? backdropPath;

  /// 剧照/背景图列表（横版），用于 PC 横屏展示
  final List<String>? backdrops;
  final double? rating;
  final int? year;
  final DateTime? firstAirDate;
  final DateTime? lastAirDate;
  final int? numberOfSeasons;
  final int? numberOfEpisodes;
  final List<String>? genres;

  /// 演员表（按展示顺序）
  final List<String>? cast;

  /// 演员详情（含头像/角色等）
  final List<CastMember>? castDetail;
  final String? tmdbId;
  final String? imdbId;
  final String? status;
  final List<Season>? seasons;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  TvShow({
    required this.id,
    required this.name,
    this.originalName,
    this.overview,
    this.posterPath,
    this.backdropPath,
    this.backdrops,
    this.rating,
    this.year,
    this.firstAirDate,
    this.lastAirDate,
    this.numberOfSeasons,
    this.numberOfEpisodes,
    this.genres,
    this.cast,
    this.castDetail,
    this.tmdbId,
    this.imdbId,
    this.status,
    this.seasons,
    this.createdAt,
    this.updatedAt,
  });

  factory TvShow.fromJson(Map<String, dynamic> json) {
    return TvShow(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: json['name'] as String? ?? json['title'] as String? ?? '',
      originalName: json['original_name'] as String?,
      overview: json['overview'] as String?,
      posterPath: json['poster_path'] as String?,
      backdropPath: json['backdrop_path'] as String?,
      backdrops: _parseGenres(json['backdrops']),
      rating: (json['vote_average'] as num?)?.toDouble(),
      year: (json['year'] as num?)?.toInt(),
      firstAirDate:
          json['first_air_date'] != null
              ? DateTime.tryParse(json['first_air_date'].toString())
              : null,
      lastAirDate:
          json['last_air_date'] != null
              ? DateTime.tryParse(json['last_air_date'].toString())
              : null,
      numberOfSeasons: (json['number_of_seasons'] as num?)?.toInt(),
      numberOfEpisodes: (json['number_of_episodes'] as num?)?.toInt(),
      genres: _parseGenres(json['genres']),
      cast: _parseGenres(json['cast']),
      castDetail: _parseCastDetail(json['cast_detail']),
      tmdbId: json['tmdb_id']?.toString(),
      imdbId: json['imdb_id']?.toString(),
      status: json['status'] as String?,
      seasons: _parseSeasons(json['seasons']),
      createdAt:
          json['created_at'] != null
              ? DateTime.tryParse(json['created_at'].toString())
              : null,
      updatedAt:
          json['updated_at'] != null
              ? DateTime.tryParse(json['updated_at'].toString())
              : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'original_name': originalName,
    'overview': overview,
    'poster_path': posterPath,
    'backdrop_path': backdropPath,
    'backdrops': backdrops,
    'vote_average': rating,
    'year': year,
    'first_air_date': firstAirDate?.toIso8601String(),
    'last_air_date': lastAirDate?.toIso8601String(),
    'number_of_seasons': numberOfSeasons,
    'number_of_episodes': numberOfEpisodes,
    'genres': genres,
    'cast': cast,
    'cast_detail': castDetail?.map((e) => e.toJson()).toList(),
    'tmdb_id': tmdbId,
    'imdb_id': imdbId,
    'status': status,
    'seasons': seasons?.map((e) => e.toJson()).toList(),
    'created_at': createdAt?.toIso8601String(),
    'updated_at': updatedAt?.toIso8601String(),
  };

  /// 获取状态显示文本
  String get statusText {
    switch (status?.toLowerCase()) {
      case 'returning series':
        return '连载中';
      case 'ended':
        return '已完结';
      case 'canceled':
        return '已取消';
      default:
        return status ?? '';
    }
  }

  static List<String>? _parseGenres(dynamic value) {
    if (value == null) return null;
    if (value is List) {
      return value.map((e) => e.toString()).toList();
    }
    if (value is String && value.isNotEmpty) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is List) {
          return decoded.map((e) => e.toString()).toList();
        }
      } catch (_) {}
    }
    return null;
  }

  static List<Season>? _parseSeasons(dynamic value) {
    if (value == null) return null;
    if (value is List) {
      return value
          .map((e) => Season.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    if (value is String && value.isNotEmpty) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is List) {
          return decoded
              .map((e) => Season.fromJson(e as Map<String, dynamic>))
              .toList();
        }
      } catch (_) {}
    }
    return null;
  }

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
}
