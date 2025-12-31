enum DownloadStatus {
  pending,
  downloading,
  paused,
  completed,
  failed,
}

class DownloadTask {
  final String id;
  final int episodeId;
  final int tvShowId;
  final int seasonId;
  final int seasonNumber;
  final int episodeNumber;
  final String episodeName;
  final String tvShowName;
  final String? fileName;
  final int? fileSize;
  final int? runtime;
  final String? storageName;
  final String downloadUrl;
  final String localPath;
  final DownloadStatus status;
  final double progress;
  final int downloadedBytes;
  final String? errorMessage;
  final DateTime createdAt;
  final DateTime? completedAt;

  DownloadTask({
    required this.id,
    required this.episodeId,
    required this.tvShowId,
    required this.seasonId,
    required this.seasonNumber,
    required this.episodeNumber,
    required this.episodeName,
    required this.tvShowName,
    this.fileName,
    this.fileSize,
    this.runtime,
    this.storageName,
    required this.downloadUrl,
    required this.localPath,
    this.status = DownloadStatus.pending,
    this.progress = 0.0,
    this.downloadedBytes = 0,
    this.errorMessage,
    required this.createdAt,
    this.completedAt,
  });

  DownloadTask copyWith({
    String? id,
    int? episodeId,
    int? tvShowId,
    int? seasonId,
    int? seasonNumber,
    int? episodeNumber,
    String? episodeName,
    String? tvShowName,
    String? fileName,
    int? fileSize,
    int? runtime,
    String? storageName,
    String? downloadUrl,
    String? localPath,
    DownloadStatus? status,
    double? progress,
    int? downloadedBytes,
    String? errorMessage,
    DateTime? createdAt,
    DateTime? completedAt,
  }) {
    return DownloadTask(
      id: id ?? this.id,
      episodeId: episodeId ?? this.episodeId,
      tvShowId: tvShowId ?? this.tvShowId,
      seasonId: seasonId ?? this.seasonId,
      seasonNumber: seasonNumber ?? this.seasonNumber,
      episodeNumber: episodeNumber ?? this.episodeNumber,
      episodeName: episodeName ?? this.episodeName,
      tvShowName: tvShowName ?? this.tvShowName,
      fileName: fileName ?? this.fileName,
      fileSize: fileSize ?? this.fileSize,
      runtime: runtime ?? this.runtime,
      storageName: storageName ?? this.storageName,
      downloadUrl: downloadUrl ?? this.downloadUrl,
      localPath: localPath ?? this.localPath,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      errorMessage: errorMessage ?? this.errorMessage,
      createdAt: createdAt ?? this.createdAt,
      completedAt: completedAt ?? this.completedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'episode_id': episodeId,
        'tv_show_id': tvShowId,
        'season_id': seasonId,
        'season_number': seasonNumber,
        'episode_number': episodeNumber,
        'episode_name': episodeName,
        'tv_show_name': tvShowName,
        'file_name': fileName,
        'file_size': fileSize,
        'runtime': runtime,
        'storage_name': storageName,
        'download_url': downloadUrl,
        'local_path': localPath,
        'status': status.index,
        'progress': progress,
        'downloaded_bytes': downloadedBytes,
        'error_message': errorMessage,
        'created_at': createdAt.toIso8601String(),
        'completed_at': completedAt?.toIso8601String(),
      };

  factory DownloadTask.fromJson(Map<String, dynamic> json) {
    return DownloadTask(
      id: json['id'] as String,
      episodeId: json['episode_id'] as int,
      tvShowId: json['tv_show_id'] as int,
      seasonId: json['season_id'] as int,
      seasonNumber: json['season_number'] as int,
      episodeNumber: json['episode_number'] as int,
      episodeName: json['episode_name'] as String,
      tvShowName: json['tv_show_name'] as String,
      fileName: json['file_name'] as String?,
      fileSize: json['file_size'] as int?,
      runtime: json['runtime'] as int?,
      storageName: json['storage_name'] as String?,
      downloadUrl: json['download_url'] as String,
      localPath: json['local_path'] as String,
      status: DownloadStatus.values[json['status'] as int],
      progress: (json['progress'] as num).toDouble(),
      downloadedBytes: json['downloaded_bytes'] as int,
      errorMessage: json['error_message'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      completedAt: json['completed_at'] != null
          ? DateTime.parse(json['completed_at'] as String)
          : null,
    );
  }

  String get displayTitle => '$episodeNumber. $episodeName';

  String get formattedFileSize {
    if (fileSize == null) return '';
    final gb = fileSize! / (1024 * 1024 * 1024);
    if (gb >= 1) return '${gb.toStringAsFixed(2)} GB';
    final mb = fileSize! / (1024 * 1024);
    return '${mb.toStringAsFixed(2)} MB';
  }

  String get formattedRuntime {
    if (runtime == null) return '';
    return '$runtime 分钟';
  }

  String get formattedProgress {
    if (fileSize == null || fileSize == 0) return '${(progress * 100).toInt()}%';
    final downloadedMB = downloadedBytes / (1024 * 1024);
    final totalMB = fileSize! / (1024 * 1024);
    return '${downloadedMB.toStringAsFixed(1)}/${totalMB.toStringAsFixed(1)} MB';
  }

  bool get isDownloading => status == DownloadStatus.downloading;
  bool get isCompleted => status == DownloadStatus.completed;
  bool get isPaused => status == DownloadStatus.paused;
  bool get isFailed => status == DownloadStatus.failed;
  bool get isPending => status == DownloadStatus.pending;
}
