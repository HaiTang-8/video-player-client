import 'dart:convert';

/// 存储源模型
class Storage {
  final int id;
  final String name;
  final String type;
  final bool enabled;
  final bool hideWhenDisabled;
  final Map<String, String>? settings;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Storage({
    required this.id,
    required this.name,
    required this.type,
    required this.enabled,
    this.hideWhenDisabled = false,
    this.settings,
    this.createdAt,
    this.updatedAt,
  });

  factory Storage.fromJson(Map<String, dynamic> json) {
    Map<String, String>? parsedSettings;
    final settingsValue = json['settings'];
    if (settingsValue is Map<String, dynamic>) {
      parsedSettings = settingsValue.cast<String, String>();
    } else if (settingsValue is String && settingsValue.isNotEmpty) {
      try {
        final decoded = jsonDecode(settingsValue);
        if (decoded is Map<String, dynamic>) {
          parsedSettings = decoded.cast<String, String>();
        }
      } catch (_) {
        // Ignore JSON parse errors
      }
    }

    return Storage(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      type: json['type'] as String? ?? '',
      enabled: json['enabled'] as bool? ?? true,
      hideWhenDisabled: json['hide_when_disabled'] as bool? ?? false,
      settings: parsedSettings,
      createdAt:
          json['created_at'] != null
              ? DateTime.tryParse(json['created_at'] as String)
              : null,
      updatedAt:
          json['updated_at'] != null
              ? DateTime.tryParse(json['updated_at'] as String)
              : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type,
    'enabled': enabled,
    'hide_when_disabled': hideWhenDisabled,
    'settings': settings,
    'created_at': createdAt?.toIso8601String(),
    'updated_at': updatedAt?.toIso8601String(),
  };

  /// 获取类型显示名称
  String get typeDisplayName {
    switch (type.toLowerCase()) {
      case 'webdav':
        return 'WebDAV';
      case 'local':
        return '本地存储';
      case 'openlist':
        return 'OpenList';
      default:
        return type;
    }
  }
}

/// 扫描进度模型
class TaskLogEntry {
  final String time;
  final String level;
  final String message;

  const TaskLogEntry({
    required this.time,
    required this.level,
    required this.message,
  });

  factory TaskLogEntry.fromJson(Map<String, dynamic> json) {
    return TaskLogEntry(
      time: json['time'] as String? ?? '',
      level: json['level'] as String? ?? 'info',
      message: json['message'] as String? ?? '',
    );
  }
}

/// 扫描进度模型
class ScanProgress {
  final int taskId;
  final int storageId;
  final String path;
  final String status;
  final String phase;
  final int discoveredFiles;
  final int totalFiles;
  final int scannedFiles;
  final double progress;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final String? error;
  final List<TaskLogEntry> logs;

  ScanProgress({
    required this.taskId,
    required this.storageId,
    this.path = '/',
    required this.status,
    this.phase = '',
    this.discoveredFiles = 0,
    required this.totalFiles,
    required this.scannedFiles,
    required this.progress,
    this.startedAt,
    this.finishedAt,
    this.error,
    this.logs = const [],
  });

  factory ScanProgress.fromJson(Map<String, dynamic> json) {
    // 解析任务日志：当前后端已将 logs 预解析为 JSON 数组返回（List），
    // 下方 String 分支仅用于兼容旧版后端直接返回 JSON 字符串的情况。
    final rawLogs = json['logs'];
    List<TaskLogEntry> parsedLogs = const [];
    if (rawLogs is List) {
      parsedLogs = rawLogs
          .whereType<Map>()
          .map(
            (entry) => TaskLogEntry.fromJson(Map<String, dynamic>.from(entry)),
          )
          .toList(growable: false);
    } else if (rawLogs is String && rawLogs.isNotEmpty) {
      // 兼容旧版后端：logs 字段可能为未预解析的 JSON 字符串
      try {
        final decoded = jsonDecode(rawLogs);
        if (decoded is List) {
          parsedLogs = decoded
              .whereType<Map>()
              .map(
                (entry) =>
                    TaskLogEntry.fromJson(Map<String, dynamic>.from(entry)),
              )
              .toList(growable: false);
        }
      } catch (_) {
        parsedLogs = const [];
      }
    }

    return ScanProgress(
      taskId: json['task_id'] as int? ?? 0,
      storageId: json['storage_id'] as int? ?? 0,
      path: json['path'] as String? ?? '/',
      status: json['status'] as String? ?? '',
      phase: json['phase'] as String? ?? '',
      discoveredFiles: json['discovered_files'] as int? ?? 0,
      totalFiles: json['total_files'] as int? ?? 0,
      scannedFiles: json['scanned_files'] as int? ?? 0,
      progress: (json['progress'] as num?)?.toDouble() ?? 0.0,
      startedAt:
          json['started_at'] != null
              ? DateTime.tryParse(json['started_at'] as String)
              : null,
      finishedAt:
          (json['finished_at'] ?? json['completed_at']) != null
              ? DateTime.tryParse(
                (json['finished_at'] ?? json['completed_at']) as String,
              )
              : null,
      error: json['error'] as String? ?? json['error_msg'] as String?,
      logs: parsedLogs,
    );
  }

  /// 是否正在运行
  bool get isRunning => status == 'running';

  /// 是否已完成
  bool get isCompleted =>
      status == 'completed' || status == 'completed_with_errors';

  /// 是否失败
  bool get isFailed => status == 'failed';

  /// 是否处于扫描发现阶段
  bool get isDiscovering => phase == 'scanning';

  /// 获取状态显示文本
  String get statusText {
    switch (status) {
      case 'running':
        return '扫描中';
      case 'completed':
        return '已完成';
      case 'completed_with_errors':
        return '完成(有错误)';
      case 'failed':
        return '失败';
      case 'cancelled':
        return '已取消';
      case 'pending':
        return '等待中';
      default:
        return status;
    }
  }
}

/// 文件信息模型（用于浏览目录）
class FileInfo {
  final String name;
  final String path;
  final bool isDir;
  final int? size;
  final DateTime? modTime;

  FileInfo({
    required this.name,
    required this.path,
    required this.isDir,
    this.size,
    this.modTime,
  });

  factory FileInfo.fromJson(Map<String, dynamic> json) {
    return FileInfo(
      name: json['name'] as String? ?? '',
      path: json['path'] as String? ?? '',
      isDir: json['is_dir'] as bool? ?? false,
      size: json['size'] as int?,
      modTime:
          json['mod_time'] != null
              ? DateTime.tryParse(json['mod_time'] as String)
              : null,
    );
  }

  /// 格式化文件大小
  String get formattedSize {
    if (size == null || isDir) return '';
    final gb = size! / (1024 * 1024 * 1024);
    if (gb >= 1) {
      return '${gb.toStringAsFixed(2)} GB';
    }
    final mb = size! / (1024 * 1024);
    if (mb >= 1) {
      return '${mb.toStringAsFixed(2)} MB';
    }
    final kb = size! / 1024;
    return '${kb.toStringAsFixed(2)} KB';
  }
}

class ScrapeTestResult {
  final String path;
  final String mediaName;
  final int year;
  final bool isTVShow;
  final int videoCount;
  final List<ScrapeTestSeasonInfo> seasons;
  final List<int> unmatchedSeasons;
  final ScrapeTestMetadata? scrape;
  final List<ScrapeSearchResult> searchResults;
  final String? error;

  const ScrapeTestResult({
    required this.path,
    required this.mediaName,
    required this.year,
    required this.isTVShow,
    required this.videoCount,
    this.seasons = const [],
    this.unmatchedSeasons = const [],
    this.scrape,
    this.searchResults = const [],
    this.error,
  });

  factory ScrapeTestResult.fromJson(Map<String, dynamic> json) {
    return ScrapeTestResult(
      path: json['path'] as String? ?? '',
      mediaName: json['media_name'] as String? ?? '',
      year: json['year'] as int? ?? 0,
      isTVShow: json['is_tv_show'] as bool? ?? false,
      videoCount: json['video_count'] as int? ?? 0,
      seasons:
          (json['seasons'] as List?)
              ?.whereType<Map>()
              .map(
                (e) =>
                    ScrapeTestSeasonInfo.fromJson(Map<String, dynamic>.from(e)),
              )
              .toList(growable: false) ??
          const [],
      unmatchedSeasons:
          (json['unmatched_seasons'] as List?)
              ?.whereType<num>()
              .map((e) => e.toInt())
              .toList(growable: false) ??
          const [],
      scrape:
          json['scrape'] is Map
              ? ScrapeTestMetadata.fromJson(
                Map<String, dynamic>.from(json['scrape'] as Map),
              )
              : null,
      searchResults:
          (json['search_results'] as List?)
              ?.whereType<Map>()
              .map(
                (e) =>
                    ScrapeSearchResult.fromJson(Map<String, dynamic>.from(e)),
              )
              .toList(growable: false) ??
          const [],
      error: json['error'] as String?,
    );
  }
}

class ScrapeTestSeasonInfo {
  final int season;
  final int episodeCount;
  final int localEpisodeCount;
  final int tmdbEpisodeCount;
  final int tmdbId;
  final bool matched;

  const ScrapeTestSeasonInfo({
    required this.season,
    required this.episodeCount,
    this.localEpisodeCount = 0,
    this.tmdbEpisodeCount = 0,
    this.tmdbId = 0,
    this.matched = false,
  });

  factory ScrapeTestSeasonInfo.fromJson(Map<String, dynamic> json) {
    final episodeCount = json['episode_count'] as int? ?? 0;
    return ScrapeTestSeasonInfo(
      season: json['season'] as int? ?? 0,
      episodeCount: episodeCount,
      localEpisodeCount: json['local_episode_count'] as int? ?? episodeCount,
      tmdbEpisodeCount: json['tmdb_episode_count'] as int? ?? 0,
      tmdbId: json['tmdb_id'] as int? ?? 0,
      matched: json['matched'] as bool? ?? false,
    );
  }

  bool get hasTMDBEpisodeCount => matched && tmdbEpisodeCount > 0;

  bool get hasEpisodeCountMismatch =>
      hasTMDBEpisodeCount && localEpisodeCount != tmdbEpisodeCount;
}

class ScrapeTestMetadata {
  final String provider;
  final int tmdbId;
  final String imdbId;
  final String title;
  final String originalTitle;
  final String overview;
  final String posterUrl;
  final String backdropUrl;
  final String releaseDate;
  final double voteAverage;
  final List<String> genres;

  const ScrapeTestMetadata({
    required this.provider,
    this.tmdbId = 0,
    this.imdbId = '',
    required this.title,
    this.originalTitle = '',
    this.overview = '',
    this.posterUrl = '',
    this.backdropUrl = '',
    this.releaseDate = '',
    this.voteAverage = 0,
    this.genres = const [],
  });

  factory ScrapeTestMetadata.fromJson(Map<String, dynamic> json) {
    return ScrapeTestMetadata(
      provider: json['provider'] as String? ?? '',
      tmdbId: json['tmdb_id'] as int? ?? 0,
      imdbId: json['imdb_id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      originalTitle: json['original_title'] as String? ?? '',
      overview: json['overview'] as String? ?? '',
      posterUrl: json['poster_url'] as String? ?? '',
      backdropUrl: json['backdrop_url'] as String? ?? '',
      releaseDate: json['release_date'] as String? ?? '',
      voteAverage: (json['vote_average'] as num?)?.toDouble() ?? 0,
      genres:
          (json['genres'] as List?)
              ?.map((e) => e.toString())
              .where((e) => e.isNotEmpty)
              .toList(growable: false) ??
          const [],
    );
  }
}

class ScrapeSearchResult {
  final int id;
  final String title;
  final String originalTitle;
  final String overview;
  final String posterPath;
  final String releaseDate;
  final double voteAverage;
  final String mediaType;
  final ScrapeCandidateScore? score;

  const ScrapeSearchResult({
    required this.id,
    required this.title,
    this.originalTitle = '',
    this.overview = '',
    this.posterPath = '',
    this.releaseDate = '',
    this.voteAverage = 0,
    this.mediaType = '',
    this.score,
  });

  factory ScrapeSearchResult.fromJson(Map<String, dynamic> json) {
    return ScrapeSearchResult(
      id: json['id'] as int? ?? 0,
      title: json['title'] as String? ?? '',
      originalTitle: json['original_title'] as String? ?? '',
      overview: json['overview'] as String? ?? '',
      posterPath: json['poster_path'] as String? ?? '',
      releaseDate: json['release_date'] as String? ?? '',
      voteAverage: (json['vote_average'] as num?)?.toDouble() ?? 0,
      mediaType: json['media_type'] as String? ?? '',
      score:
          json['score'] is Map
              ? ScrapeCandidateScore.fromJson(
                Map<String, dynamic>.from(json['score'] as Map),
              )
              : null,
    );
  }
}

class ScrapeCandidateScore {
  final int total;
  final int title;
  final int year;
  final int rank;
  final int vote;
  final int episode;
  final bool confident;
  final bool selected;
  final int localEpisodeCount;
  final int tmdbEpisodeCount;

  const ScrapeCandidateScore({
    this.total = 0,
    this.title = 0,
    this.year = 0,
    this.rank = 0,
    this.vote = 0,
    this.episode = 0,
    this.confident = false,
    this.selected = false,
    this.localEpisodeCount = 0,
    this.tmdbEpisodeCount = 0,
  });

  factory ScrapeCandidateScore.fromJson(Map<String, dynamic> json) {
    return ScrapeCandidateScore(
      total: json['total'] as int? ?? 0,
      title: json['title'] as int? ?? 0,
      year: json['year'] as int? ?? 0,
      rank: json['rank'] as int? ?? 0,
      vote: json['vote'] as int? ?? 0,
      episode: json['episode'] as int? ?? 0,
      confident: json['confident'] as bool? ?? false,
      selected: json['selected'] as bool? ?? false,
      localEpisodeCount: json['local_episode_count'] as int? ?? 0,
      tmdbEpisodeCount: json['tmdb_episode_count'] as int? ?? 0,
    );
  }
}

/// 存储源导入结果
class StorageImportResult {
  final int successCount;
  final int skippedCount;
  final List<String> skippedNames;
  final List<String>? errors;

  StorageImportResult({
    required this.successCount,
    required this.skippedCount,
    required this.skippedNames,
    this.errors,
  });

  factory StorageImportResult.fromJson(Map<String, dynamic> json) {
    return StorageImportResult(
      successCount: json['success_count'] as int? ?? 0,
      skippedCount: json['skipped_count'] as int? ?? 0,
      skippedNames:
          (json['skipped_names'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      errors:
          (json['errors'] as List<dynamic>?)?.map((e) => e as String).toList(),
    );
  }
}
