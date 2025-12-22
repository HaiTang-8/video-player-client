// AI 整理相关模型
//
// 说明：
// - preview：仅返回“建议方案”，不会修改任何文件
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

class AiTidyPlan {
  final String provider;
  final int storageId;
  final String rootPath;
  final String snapshotHash;
  final int fileCount;
  final List<AiTidyOperation> operations;
  final String summary;
  final List<String> warnings;

  const AiTidyPlan({
    required this.provider,
    required this.storageId,
    required this.rootPath,
    required this.snapshotHash,
    required this.fileCount,
    required this.operations,
    required this.summary,
    required this.warnings,
  });

  factory AiTidyPlan.fromJson(Map<String, dynamic> json) {
    final ops =
        (json['operations'] as List? ?? [])
            .map((e) => AiTidyOperation.fromJson(e as Map<String, dynamic>))
            .toList();
    final warnings =
        (json['warnings'] as List? ?? []).map((e) => e.toString()).toList();

    return AiTidyPlan(
      provider: json['provider'] as String? ?? '',
      storageId: json['storage_id'] as int? ?? 0,
      rootPath: json['root_path'] as String? ?? '/',
      snapshotHash: json['snapshot_hash'] as String? ?? '',
      fileCount: json['file_count'] as int? ?? 0,
      operations: ops,
      summary: json['summary'] as String? ?? '',
      warnings: warnings,
    );
  }
}

class AiTidyApplyResult {
  final int applied;

  const AiTidyApplyResult({required this.applied});

  factory AiTidyApplyResult.fromJson(Map<String, dynamic> json) {
    return AiTidyApplyResult(applied: json['applied'] as int? ?? 0);
  }
}
