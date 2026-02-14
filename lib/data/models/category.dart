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
  final String? backdropPath;
  final int? year;
  final WatchHistoryEpisodeInfo? episodeInfo;

  WatchHistoryMediaInfo({
    required this.title,
    this.posterPath,
    this.backdropPath,
    this.year,
    this.episodeInfo,
  });

  factory WatchHistoryMediaInfo.fromJson(Map<String, dynamic> json) {
    return WatchHistoryMediaInfo(
      title: json['title'] as String? ?? '',
      posterPath: json['poster_path'] as String?,
      backdropPath: json['backdrop_path'] as String?,
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
  final int seasonId;
  final int seasonNumber;
  final int episodeNumber;
  final String? episodeName;
  final String? stillPath;

  WatchHistoryEpisodeInfo({
    required this.seasonId,
    required this.seasonNumber,
    required this.episodeNumber,
    this.episodeName,
    this.stillPath,
  });

  factory WatchHistoryEpisodeInfo.fromJson(Map<String, dynamic> json) {
    return WatchHistoryEpisodeInfo(
      seasonId: (json['season_id'] as num?)?.toInt() ?? 0,
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
  final int? tmdbMediaId;
  final int? tmdbEpisodeId;
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
    this.tmdbMediaId,
    this.tmdbEpisodeId,
    required this.position,
    required this.duration,
    required this.completed,
    required this.watchedAt,
    this.mediaInfo,
  });

  /// 计算播放进度（0.0 - 1.0）
  double get progress => duration > 0 ? (position / duration).clamp(0.0, 1.0) : 0.0;

  /// 构建播放标题（用于播放器显示）
  String buildTitle() {
    final mediaInfo = this.mediaInfo;
    if (mediaInfo == null) return '';
    final episodeInfo = mediaInfo.episodeInfo;
    if (mediaType == 'tv' && episodeInfo != null) {
      final parts = <String>[mediaInfo.title];
      if (episodeInfo.seasonNumber > 0) {
        parts.add('第${episodeInfo.seasonNumber}季');
      }
      parts.add('第${episodeInfo.episodeNumber}集');
      if (episodeInfo.episodeName != null && episodeInfo.episodeName!.isNotEmpty) {
        parts.add(episodeInfo.episodeName!);
      }
      return parts.join(' ');
    }
    return mediaInfo.title;
  }

  factory WatchHistoryItem.fromJson(Map<String, dynamic> json) {
    return WatchHistoryItem(
      id: (json['id'] as num?)?.toInt() ?? 0,
      mediaType: json['media_type'] as String? ?? '',
      mediaId: (json['media_id'] as num?)?.toInt() ?? 0,
      episodeId: (json['episode_id'] as num?)?.toInt(),
      tmdbMediaId: (json['tmdb_media_id'] as num?)?.toInt(),
      tmdbEpisodeId: (json['tmdb_episode_id'] as num?)?.toInt(),
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
        if (tmdbMediaId != null) 'tmdb_media_id': tmdbMediaId,
        if (tmdbEpisodeId != null) 'tmdb_episode_id': tmdbEpisodeId,
        'position': position,
        'duration': duration,
        'completed': completed,
        'watched_at': watchedAt.toIso8601String(),
      };
}

/// 观看历史合并分组（按剧集媒体合并）
class WatchHistoryGroup {
  /// 媒体类型（movie/tv）
  final String mediaType;

  /// 媒体 ID（电影或电视剧的本地 ID）
  final int mediaId;

  /// 同一媒体下的所有观看记录（已按 watchedAt 倒序）
  final List<WatchHistoryItem> items;

  /// 组内主展示记录（默认最新观看的一集/一条）
  final WatchHistoryItem primaryItem;

  /// 组内最新观看时间（用于外部排序）
  final DateTime latestWatchedAt;

  WatchHistoryGroup({
    required this.mediaType,
    required this.mediaId,
    required this.items,
    required this.primaryItem,
    required this.latestWatchedAt,
  });

  /// 该组包含的记录数量
  int get count => items.length;

  /// 是否为多集剧集（只有剧集且数量>1才认为多集）
  bool get isMultiEpisode => mediaType == 'tv' && items.length > 1;

  /// 将观看历史列表按剧集合并为分组
  static List<WatchHistoryGroup> groupItems(
    List<WatchHistoryItem> items, {
    bool mergeEpisodes = true,
  }) {
    if (items.isEmpty) {
      return const [];
    }

    // 先按观看时间倒序，保证分组后的顺序与“最新观看”一致
    final sortedItems = List<WatchHistoryItem>.from(items)
      ..sort((a, b) => b.watchedAt.compareTo(a.watchedAt));

    // 分组容器：key -> items，且记录首次出现顺序
    final Map<String, List<WatchHistoryItem>> groupedMap = {};
    final List<String> orderedKeys = [];

    for (final item in sortedItems) {
      final bool canMergeAsShow = mergeEpisodes &&
          item.mediaType == 'tv' &&
          item.mediaInfo?.episodeInfo != null;
      final tmdb = item.tmdbMediaId ?? 0;
      final tmdbEp = item.tmdbEpisodeId ?? 0;

      final String groupKey;
      if (canMergeAsShow) {
        groupKey = tmdb > 0
            ? 'tv_tmdb_$tmdb'
            : 'tv_${item.mediaId}';
      } else if (tmdb > 0) {
        if (item.mediaType == 'tv' && tmdbEp > 0) {
          groupKey = 'tv_tmdb_${tmdb}_$tmdbEp';
        } else if (item.mediaType == 'tv') {
          groupKey = 'tv_${item.mediaId}_${item.episodeId ?? 0}_${item.id}';
        } else {
          groupKey = 'movie_tmdb_$tmdb';
        }
      } else {
        groupKey = '${item.mediaType}_${item.mediaId}_${item.episodeId ?? 0}_${item.id}';
      }

      if (!groupedMap.containsKey(groupKey)) {
        groupedMap[groupKey] = [];
        orderedKeys.add(groupKey);
      }
      groupedMap[groupKey]!.add(item);
    }

    // 组装分组列表，并确保每组内部仍按最新观看优先
    final List<WatchHistoryGroup> groups = [];
    for (final key in orderedKeys) {
      final groupItems = groupedMap[key]!;
      groupItems.sort((a, b) => b.watchedAt.compareTo(a.watchedAt));
      final primaryItem = groupItems.first;
      groups.add(
        WatchHistoryGroup(
          mediaType: primaryItem.mediaType,
          mediaId: primaryItem.mediaId,
          items: groupItems,
          primaryItem: primaryItem,
          latestWatchedAt: primaryItem.watchedAt,
        ),
      );
    }

    return groups;
  }
}
