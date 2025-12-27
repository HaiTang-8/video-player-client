/// 分类统计数据
class CategoryStats {
  final String id;
  final String displayName;
  final int count;

  CategoryStats({
    required this.id,
    required this.displayName,
    required this.count,
  });

  factory CategoryStats.fromJson(Map<String, dynamic> json) {
    return CategoryStats(
      id: json['id'] as String? ?? '',
      displayName: json['display_name'] as String? ?? '',
      count: (json['count'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'display_name': displayName,
        'count': count,
      };
}

/// 观看历史媒体信息
class WatchHistoryMediaInfo {
  final String title;
  final String? posterPath;
  final int? year;
  final WatchHistoryEpisodeInfo? episodeInfo;

  WatchHistoryMediaInfo({
    required this.title,
    this.posterPath,
    this.year,
    this.episodeInfo,
  });

  factory WatchHistoryMediaInfo.fromJson(Map<String, dynamic> json) {
    return WatchHistoryMediaInfo(
      title: json['title'] as String? ?? '',
      posterPath: json['poster_path'] as String?,
      year: (json['year'] as num?)?.toInt(),
      episodeInfo: json['episode_info'] != null
          ? WatchHistoryEpisodeInfo.fromJson(
              json['episode_info'] as Map<String, dynamic>)
          : null,
    );
  }
}

/// 观看历史剧集详细信息
class WatchHistoryEpisodeInfo {
  final int seasonNumber;
  final int episodeNumber;
  final String? episodeName;
  final String? stillPath;

  WatchHistoryEpisodeInfo({
    required this.seasonNumber,
    required this.episodeNumber,
    this.episodeName,
    this.stillPath,
  });

  factory WatchHistoryEpisodeInfo.fromJson(Map<String, dynamic> json) {
    return WatchHistoryEpisodeInfo(
      seasonNumber: (json['season_number'] as num?)?.toInt() ?? 0,
      episodeNumber: (json['episode_number'] as num?)?.toInt() ?? 0,
      episodeName: json['episode_name'] as String?,
      stillPath: json['still_path'] as String?,
    );
  }
}

/// 观看历史项
class WatchHistoryItem {
  final int id;
  final String mediaType;
  final int mediaId;
  final int? episodeId;
  final int position;
  final int duration;
  final bool completed;
  final DateTime watchedAt;
  final WatchHistoryMediaInfo? mediaInfo;

  WatchHistoryItem({
    required this.id,
    required this.mediaType,
    required this.mediaId,
    this.episodeId,
    required this.position,
    required this.duration,
    required this.completed,
    required this.watchedAt,
    this.mediaInfo,
  });

  /// 计算播放进度（0.0 - 1.0）
  double get progress => duration > 0 ? position / duration : 0;

  factory WatchHistoryItem.fromJson(Map<String, dynamic> json) {
    return WatchHistoryItem(
      id: (json['id'] as num?)?.toInt() ?? 0,
      mediaType: json['media_type'] as String? ?? '',
      mediaId: (json['media_id'] as num?)?.toInt() ?? 0,
      episodeId: (json['episode_id'] as num?)?.toInt(),
      position: (json['position'] as num?)?.toInt() ?? 0,
      duration: (json['duration'] as num?)?.toInt() ?? 0,
      completed: json['completed'] as bool? ?? false,
      watchedAt: json['watched_at'] != null
          ? DateTime.parse(json['watched_at'] as String)
          : DateTime.now(),
      mediaInfo: json['media_info'] != null
          ? WatchHistoryMediaInfo.fromJson(
              json['media_info'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'media_type': mediaType,
        'media_id': mediaId,
        'episode_id': episodeId,
        'position': position,
        'duration': duration,
        'completed': completed,
        'watched_at': watchedAt.toIso8601String(),
      };
}
