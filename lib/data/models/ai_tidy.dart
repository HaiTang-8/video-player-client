// AI 整理相关模型
//
// 说明：
// - preview：仅返回"建议方案"，不会修改任何文件
// - apply：需要用户二次确认后执行，会对文件做移动/重命名

class AiTidyOperation {
  final String from;
  final String to;
  final String? reason;

  const AiTidyOperation({required this.from, required this.to, this.reason});

  factory AiTidyOperation.fromJson(Map<String, dynamic> json) {
    return AiTidyOperation(
      from: json['from'] as String? ?? '',
      to: json['to'] as String? ?? '',
      reason: json['reason'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'from': from,
    'to': to,
    if (reason != null) 'reason': reason,
  };
}

/// 单个扫描文件的识别信息（用于展示识别链路）
class AiTidyFileInfo {
  final int id;
  final String path;
  final String name;
  final bool isVideo;
  final bool isSubtitle;
  final String? parsedTitle;
  final int? parsedYear;
  final bool parsedIsTVShow;
  final bool hasChange;
  final String? newPath;
  final String? reason;

  const AiTidyFileInfo({
    required this.id,
    required this.path,
    required this.name,
    this.isVideo = false,
    this.isSubtitle = false,
    this.parsedTitle,
    this.parsedYear,
    this.parsedIsTVShow = false,
    this.hasChange = false,
    this.newPath,
    this.reason,
  });

  factory AiTidyFileInfo.fromJson(Map<String, dynamic> json) {
    return AiTidyFileInfo(
      id: json['id'] as int? ?? 0,
      path: json['path'] as String? ?? '',
      name: json['name'] as String? ?? '',
      isVideo: json['is_video'] as bool? ?? false,
      isSubtitle: json['is_subtitle'] as bool? ?? false,
      parsedTitle: json['parsed_title'] as String?,
      parsedYear: json['parsed_year'] as int?,
      parsedIsTVShow: json['parsed_is_tv_show'] as bool? ?? false,
      hasChange: json['has_change'] as bool? ?? false,
      newPath: json['new_path'] as String?,
      reason: json['reason'] as String?,
    );
  }
}

/// TMDB 查询结果
class AiTidyTMDBResult {
  final String title;
  final String? originalTitle;
  final int? year;

  const AiTidyTMDBResult({required this.title, this.originalTitle, this.year});

  factory AiTidyTMDBResult.fromJson(Map<String, dynamic> json) {
    return AiTidyTMDBResult(
      title: json['title'] as String? ?? '',
      originalTitle: json['original_title'] as String?,
      year: json['year'] as int?,
    );
  }
}

/// TMDB 查询提示
class AiTidyTMDBHint {
  final String query;
  final int? year;
  final bool isTVShow;
  final List<AiTidyTMDBResult> results;

  const AiTidyTMDBHint({
    required this.query,
    this.year,
    this.isTVShow = false,
    this.results = const [],
  });

  factory AiTidyTMDBHint.fromJson(Map<String, dynamic> json) {
    return AiTidyTMDBHint(
      query: json['query'] as String? ?? '',
      year: json['year'] as int?,
      isTVShow: json['is_tv_show'] as bool? ?? false,
      results: (json['results'] as List? ?? [])
          .map((e) => AiTidyTMDBResult.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class AiTidyPlan {
  final String provider;
  final int storageId;
  final String rootPath;
  final String snapshotHash;
  final int fileCount;
  final List<AiTidyOperation> operations;
  final String summary;
  final List<String> warnings;
  final List<AiTidyFileInfo> files;
  final List<AiTidyTMDBHint> tmdbHints;

  const AiTidyPlan({
    required this.provider,
    required this.storageId,
    required this.rootPath,
    required this.snapshotHash,
    required this.fileCount,
    required this.operations,
    required this.summary,
    required this.warnings,
    this.files = const [],
    this.tmdbHints = const [],
  });

  factory AiTidyPlan.fromJson(Map<String, dynamic> json) {
    final ops =
        (json['operations'] as List? ?? [])
            .map((e) => AiTidyOperation.fromJson(e as Map<String, dynamic>))
            .toList();
    final warnings =
        (json['warnings'] as List? ?? []).map((e) => e.toString()).toList();
    final files =
        (json['files'] as List? ?? [])
            .map((e) => AiTidyFileInfo.fromJson(e as Map<String, dynamic>))
            .toList();
    final tmdbHints =
        (json['tmdb_hints'] as List? ?? [])
            .map((e) => AiTidyTMDBHint.fromJson(e as Map<String, dynamic>))
            .toList();

    return AiTidyPlan(
      provider: json['provider'] as String? ?? '',
      storageId: json['storage_id'] as int? ?? 0,
      rootPath: json['root_path'] as String? ?? '/',
      snapshotHash: json['snapshot_hash'] as String? ?? '',
      fileCount: json['file_count'] as int? ?? 0,
      operations: ops,
      summary: json['summary'] as String? ?? '',
      warnings: warnings,
      files: files,
      tmdbHints: tmdbHints,
    );
  }
}

class AiTidyApplyResult {
  final int applied;
  final int dbUpdated;
  final int dbCreated;
  final int dbDeleted;

  const AiTidyApplyResult({
    required this.applied,
    this.dbUpdated = 0,
    this.dbCreated = 0,
    this.dbDeleted = 0,
  });

  factory AiTidyApplyResult.fromJson(Map<String, dynamic> json) {
    return AiTidyApplyResult(
      applied: json['applied'] as int? ?? 0,
      dbUpdated: json['db_updated'] as int? ?? 0,
      dbCreated: json['db_created'] as int? ?? 0,
      dbDeleted: json['db_deleted'] as int? ?? 0,
    );
  }
}
