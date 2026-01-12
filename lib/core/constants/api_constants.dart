/// API 相关常量
class ApiConstants {
  ApiConstants._();

  static const String apiVersion = 'v1';
  static const String apiPrefix = '/api/$apiVersion';

  // 媒体库
  static const String libraryPosters = '$apiPrefix/library/posters';
  static const String libraryCategories = '$apiPrefix/library/categories';
  static const String librarySearch = '$apiPrefix/library/search';

  // 观看历史
  static const String historyRecent = '$apiPrefix/history/recent';
  static const String historyUpdate = '$apiPrefix/history';
  static String historyGet(String mediaType, int mediaId) =>
      '$apiPrefix/history/$mediaType/$mediaId';
  static String historyEpisodeProgress(int tvShowId, int episodeId) =>
      '$apiPrefix/history/episode/$tvShowId/$episodeId';
  static String historyDelete(int id) => '$apiPrefix/history/$id';
  static const String historyBatchDelete = '$apiPrefix/history/batch-delete';
  static const String historyDeleteAll = '$apiPrefix/history';

  // 电影
  static const String movies = '$apiPrefix/movies';
  static String movieDetail(int id) => '$apiPrefix/movies/$id';
  static String movieStream(int id) => '$apiPrefix/movies/$id/stream';
  static String movieScrape(int id) => '$apiPrefix/movies/$id/scrape';
  static String movieImages(int id) => '$apiPrefix/movies/$id/images';
  static String moviePoster(int id) => '$apiPrefix/movies/$id/poster';
  static const String movieSearch = '$apiPrefix/movies/search';
  static const String movieTmdbSearch = '$apiPrefix/movies/tmdb/search';

  // 剧集
  static const String tvShows = '$apiPrefix/tvshows';
  static String tvShowDetail(int id) => '$apiPrefix/tvshows/$id';
  static String tvShowSeasons(int id) => '$apiPrefix/tvshows/$id/seasons';
  static String tvShowEpisodes(int tvShowId, int seasonId) =>
      '$apiPrefix/tvshows/$tvShowId/seasons/$seasonId/episodes';
  static String episodeStream(int tvShowId, int seasonId, int episodeId) =>
      '$apiPrefix/tvshows/$tvShowId/seasons/$seasonId/episodes/$episodeId/stream';
  static String seasonSourceGroups(int tvShowId, int seasonId) =>
      '$apiPrefix/tvshows/$tvShowId/seasons/$seasonId/source-groups';
  static String seasonPrimarySource(int tvShowId, int seasonId) =>
      '$apiPrefix/tvshows/$tvShowId/seasons/$seasonId/primary-source';
  static String tvShowScrape(int id) => '$apiPrefix/tvshows/$id/scrape';
  static String tvShowAiMatch(int id) => '$apiPrefix/tvshows/$id/ai-match';
  static String tvShowImages(int id) => '$apiPrefix/tvshows/$id/images';
  static String tvShowPoster(int id) => '$apiPrefix/tvshows/$id/poster';
  static String seasonPoster(int tvShowId, int seasonId) =>
      '$apiPrefix/tvshows/$tvShowId/seasons/$seasonId/poster';
  static const String tvShowSearch = '$apiPrefix/tvshows/search';
  static const String tvShowTmdbSearch = '$apiPrefix/tvshows/tmdb/search';

  // 存储源
  static const String storages = '$apiPrefix/storages';
  static String storageDetail(int id) => '$apiPrefix/storages/$id';
  static String storageScan(int id) => '$apiPrefix/storages/$id/scan';
  static String storageScanProgress(int id) =>
      '$apiPrefix/storages/$id/scan/progress';
  static String storageScanTasks(int id) =>
      '$apiPrefix/storages/$id/scan/tasks';
  static String storageBrowse(int id) => '$apiPrefix/storages/$id/browse';
  static String storageAiTidyPreview(int id) =>
      '$apiPrefix/storages/$id/ai-tidy/preview';
  static String storageAiTidyApply(int id) =>
      '$apiPrefix/storages/$id/ai-tidy/apply';

  // 任务
  static const String tasksRunning = '$apiPrefix/tasks/running';
  static String taskDetail(int taskId) => '$apiPrefix/tasks/$taskId';
  static String taskCancel(int taskId) => '$apiPrefix/tasks/$taskId/cancel';
  static const String tasksCancelAll = '$apiPrefix/tasks/cancel-all';

  // 字幕
  static const String subtitles = '$apiPrefix/subtitles';

  // 下载直链
  static String downloadMovieUrl(int id) => '$apiPrefix/download/movie/$id/url';
  static String downloadSourceUrl(int id) => '$apiPrefix/download/source/$id/url';

  // 健康检查
  static const String health = '/health';

  // 数据库备份
  static const String databaseBackups = '$apiPrefix/system/database/backups';
  static String databaseBackupDelete(String name) =>
      '$apiPrefix/system/database/backups/$name';
  static const String databaseRollback = '$apiPrefix/system/database/rollback';
}
