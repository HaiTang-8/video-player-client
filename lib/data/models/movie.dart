import 'dart:convert';

/// 电影模型
class Movie {
  final int id;
  final String title;
  final String? originalTitle;
  final String? overview;
  final String? posterPath;
  final String? backdropPath;
  final double? rating;
  final int? year;
  final DateTime? releaseDate;
  final int? runtime;
  final List<String>? genres;
  final String? tmdbId;
  final String? imdbId;
  final String? filePath;
  final int? fileSize;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Movie({
    required this.id,
    required this.title,
    this.originalTitle,
    this.overview,
    this.posterPath,
    this.backdropPath,
    this.rating,
    this.year,
    this.releaseDate,
    this.runtime,
    this.genres,
    this.tmdbId,
    this.imdbId,
    this.filePath,
    this.fileSize,
    this.createdAt,
    this.updatedAt,
  });

  factory Movie.fromJson(Map<String, dynamic> json) {
    return Movie(
      id: (json['id'] as num?)?.toInt() ?? 0,
      title: json['title'] as String? ?? '',
      originalTitle: json['original_title'] as String?,
      overview: json['overview'] as String?,
      posterPath: json['poster_path'] as String?,
      backdropPath: json['backdrop_path'] as String?,
      rating: (json['vote_average'] as num?)?.toDouble(),
      year: (json['year'] as num?)?.toInt(),
      releaseDate: json['release_date'] != null
          ? DateTime.tryParse(json['release_date'].toString())
          : null,
      runtime: (json['runtime'] as num?)?.toInt(),
      genres: _parseGenres(json['genres']),
      tmdbId: json['tmdb_id']?.toString(),
      imdbId: json['imdb_id']?.toString(),
      filePath: json['file_path'] as String?,
      fileSize: (json['file_size'] as num?)?.toInt(),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'original_title': originalTitle,
        'overview': overview,
        'poster_path': posterPath,
        'backdrop_path': backdropPath,
        'vote_average': rating,
        'year': year,
        'release_date': releaseDate?.toIso8601String(),
        'runtime': runtime,
        'genres': genres,
        'tmdb_id': tmdbId,
        'imdb_id': imdbId,
        'file_path': filePath,
        'file_size': fileSize,
        'created_at': createdAt?.toIso8601String(),
        'updated_at': updatedAt?.toIso8601String(),
      };

  /// 格式化时长
  String get formattedRuntime {
    if (runtime == null) return '';
    final hours = runtime! ~/ 60;
    final minutes = runtime! % 60;
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m';
  }

  /// 格式化文件大小
  String get formattedFileSize {
    if (fileSize == null) return '';
    final gb = fileSize! / (1024 * 1024 * 1024);
    if (gb >= 1) {
      return '${gb.toStringAsFixed(2)} GB';
    }
    final mb = fileSize! / (1024 * 1024);
    return '${mb.toStringAsFixed(2)} MB';
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
}
