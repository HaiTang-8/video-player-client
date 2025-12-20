/// 剧集集数模型
class Episode {
  final int id;
  final int tvShowId;
  final int seasonId;
  final int seasonNumber;
  final int episodeNumber;
  final String? name;
  final String? overview;
  final String? stillPath;
  final DateTime? airDate;
  final int? runtime;
  final double? rating;
  final String? filePath;
  final int? fileSize;

  Episode({
    required this.id,
    required this.tvShowId,
    required this.seasonId,
    required this.seasonNumber,
    required this.episodeNumber,
    this.name,
    this.overview,
    this.stillPath,
    this.airDate,
    this.runtime,
    this.rating,
    this.filePath,
    this.fileSize,
  });

  factory Episode.fromJson(Map<String, dynamic> json) {
    return Episode(
      id: (json['id'] as num?)?.toInt() ?? 0,
      tvShowId: (json['tv_show_id'] as num?)?.toInt() ?? 0,
      seasonId: (json['season_id'] as num?)?.toInt() ?? 0,
      seasonNumber: (json['season_number'] as num?)?.toInt() ?? 0,
      episodeNumber: (json['episode_number'] as num?)?.toInt() ?? 0,
      name: json['name'] as String?,
      overview: json['overview'] as String?,
      stillPath: json['still_path'] as String?,
      airDate: json['air_date'] != null
          ? DateTime.tryParse(json['air_date'].toString())
          : null,
      runtime: (json['runtime'] as num?)?.toInt(),
      rating: (json['vote_average'] as num?)?.toDouble(),
      filePath: json['file_path'] as String?,
      fileSize: (json['file_size'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'tv_show_id': tvShowId,
        'season_id': seasonId,
        'season_number': seasonNumber,
        'episode_number': episodeNumber,
        'name': name,
        'overview': overview,
        'still_path': stillPath,
        'air_date': airDate?.toIso8601String(),
        'runtime': runtime,
        'vote_average': rating,
        'file_path': filePath,
        'file_size': fileSize,
      };

  /// 显示标题
  String get displayTitle {
    final ep = 'E$episodeNumber';
    if (name != null && name!.isNotEmpty) {
      return '$ep $name';
    }
    return '第 $episodeNumber 集';
  }

  /// 是否有视频文件
  bool get hasFile => filePath != null && filePath!.isNotEmpty;

  /// 格式化时长
  String get formattedRuntime {
    if (runtime == null) return '';
    return '$runtime分钟';
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
}
