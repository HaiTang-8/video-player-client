enum DownloadStatus {
  pending,
  downloading,
  paused,
  completed,
  failed,
}

enum DownloadType {
  movie,
  episode,
}

class DownloadTask {
  final String id;
  final DownloadType type;
  // Movie fields
  final int? movieId;
  final String? movieTitle;
  // Episode fields
  final int? episodeId;
  final int? tvShowId;
  final int? seasonId;
  final int? seasonNumber;
  final int? episodeNumber;
  final String? episodeName;
  final String? tvShowName;
  // Common fields
  final String? fileName;
  final int? fileSize;
  final int? runtime;
  final String? storageName;
  final String downloadUrl;
  final String localPath;
  final DownloadStatus status;
  final double progress;
  final int downloadedBytes;
  final double downloadSpeed;
  final String? errorMessage;
  final DateTime createdAt;
  final DateTime? completedAt;
  final String? aria2Gid;

  DownloadTask({
    required this.id,
    required this.type,
    this.movieId,
    this.movieTitle,
    this.episodeId,
    this.tvShowId,
    this.seasonId,
    this.seasonNumber,
    this.episodeNumber,
    this.episodeName,
    this.tvShowName,
    this.fileName,
    this.fileSize,
    this.runtime,
    this.storageName,
    required this.downloadUrl,
    required this.localPath,
    this.status = DownloadStatus.pending,
    this.progress = 0.0,
    this.downloadedBytes = 0,
    this.downloadSpeed = 0,
    this.errorMessage,
    required this.createdAt,
    this.completedAt,
    this.aria2Gid,
  });

  DownloadTask copyWith({
    String? id,
    DownloadType? type,
    int? movieId,
    String? movieTitle,
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
    double? downloadSpeed,
    String? errorMessage,
    DateTime? createdAt,
    DateTime? completedAt,
    String? aria2Gid,
  }) {
    return DownloadTask(
      id: id ?? this.id,
      type: type ?? this.type,
      movieId: movieId ?? this.movieId,
      movieTitle: movieTitle ?? this.movieTitle,
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
      downloadSpeed: downloadSpeed ?? this.downloadSpeed,
      errorMessage: errorMessage ?? this.errorMessage,
      createdAt: createdAt ?? this.createdAt,
      completedAt: completedAt ?? this.completedAt,
      aria2Gid: aria2Gid ?? this.aria2Gid,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.index,
        'movie_id': movieId,
        'movie_title': movieTitle,
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
        'aria2_gid': aria2Gid,
      };

  factory DownloadTask.fromJson(Map<String, dynamic> json) {
    return DownloadTask(
      id: json['id'] as String,
      type: json['type'] != null
          ? DownloadType.values[json['type'] as int]
          : DownloadType.episode,
      movieId: json['movie_id'] as int?,
      movieTitle: json['movie_title'] as String?,
      episodeId: json['episode_id'] as int?,
      tvShowId: json['tv_show_id'] as int?,
      seasonId: json['season_id'] as int?,
      seasonNumber: json['season_number'] as int?,
      episodeNumber: json['episode_number'] as int?,
      episodeName: json['episode_name'] as String?,
      tvShowName: json['tv_show_name'] as String?,
      fileName: json['file_name'] as String?,
      fileSize: json['file_size'] as int?,
      runtime: json['runtime'] as int?,
      storageName: json['storage_name'] as String?,
      downloadUrl: json['download_url'] as String,
      localPath: json['local_path'] as String,
      status: DownloadStatus.values[json['status'] as int],
      progress: (json['progress'] as num).toDouble(),
      downloadedBytes: json['downloaded_bytes'] as int,
      downloadSpeed: 0,
      errorMessage: json['error_message'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      completedAt: json['completed_at'] != null
          ? DateTime.parse(json['completed_at'] as String)
          : null,
      aria2Gid: json['aria2_gid'] as String?,
    );
  }

  String get displayTitle {
    if (type == DownloadType.movie) {
      return movieTitle ?? '未知电影';
    }
    if (episodeNumber != null && episodeName != null) {
      return '$episodeNumber. $episodeName';
    }
    return episodeName ?? '未知剧集';
  }

  String get liveActivityTitle {
    if (type == DownloadType.movie) {
      return movieTitle ?? '未知电影';
    }
    final sNum = seasonNumber?.toString().padLeft(2, '0') ?? '01';
    final eNum = episodeNumber?.toString().padLeft(2, '0') ?? '01';
    return '${tvShowName ?? '未知剧集'}.S$sNum.E$eNum';
  }

  String get displaySubtitle {
    if (type == DownloadType.movie) {
      return storageName ?? '';
    }
    final parts = <String>[];
    if (tvShowName != null) parts.add(tvShowName!);
    if (seasonNumber != null) parts.add('第 $seasonNumber 季');
    return parts.join(' · ');
  }

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

  String get formattedSpeed {
    if (downloadSpeed <= 0) return '0 B/s';
    if (downloadSpeed < 1024) {
      return '${downloadSpeed.toStringAsFixed(0)} B/s';
    }
    final speedKB = downloadSpeed / 1024;
    if (speedKB < 1024) {
      return '${speedKB.toStringAsFixed(0)} KB/s';
    }
    final speedMB = speedKB / 1024;
    return '${speedMB.toStringAsFixed(2)} MB/s';
  }

  bool get isMovie => type == DownloadType.movie;
  bool get isEpisode => type == DownloadType.episode;
  bool get isDownloading => status == DownloadStatus.downloading;
  bool get isCompleted => status == DownloadStatus.completed;
  bool get isPaused => status == DownloadStatus.paused;
  bool get isFailed => status == DownloadStatus.failed;
  bool get isPending => status == DownloadStatus.pending;
}
