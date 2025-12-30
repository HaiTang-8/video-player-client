class DatabaseBackupInfo {
  final String name;
  final int size;
  final DateTime createdAt;

  DatabaseBackupInfo({
    required this.name,
    required this.size,
    required this.createdAt,
  });

  factory DatabaseBackupInfo.fromJson(Map<String, dynamic> json) {
    return DatabaseBackupInfo(
      name: json['name'] as String? ?? '',
      size: json['size'] as int? ?? 0,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }

  String get formattedSize {
    final mb = size / (1024 * 1024);
    if (mb >= 1) return '${mb.toStringAsFixed(2)} MB';
    final kb = size / 1024;
    return '${kb.toStringAsFixed(2)} KB';
  }
}
