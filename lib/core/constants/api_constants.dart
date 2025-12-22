/// API 相关常量
class ApiConstants {
  ApiConstants._();

  static const String apiVersion = 'v1';
  static const String apiPrefix = '/api/$apiVersion';

  // 媒体库
  static const String libraryPosters = '$apiPrefix/library/posters';
  static const String libraryCategories = '$apiPrefix/library/categories';

  // 观看历史
  static const String historyRecent = '$apiPrefix/history/recent';
  static const String historyUpdate = '$apiPrefix/history';
  static String historyGet(String mediaType, int mediaId) =>
      '$apiPrefix/history/$mediaType/$mediaId';

  // 电影
  static const String movies = '$apiPrefix/movies';
  static String movieDetail(int id) => '$apiPrefix/movies/$id';
  static String movieStream(int id) => '$apiPrefix/movies/$id/stream';
  static String movieScrape(int id) => '$apiPrefix/movies/$id/scrape';
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
  static String tvShowScrape(int id) => '$apiPrefix/tvshows/$id/scrape';
  static String tvShowAiMatch(int id) => '$apiPrefix/tvshows/$id/ai-match';
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

  // 健康检查
  static const String health = '/health';
}
