import '../models/models.dart';
import '../../core/constants/api_constants.dart';
import 'api_client.dart';

/// 媒体服务
class MediaService {
  final ApiClient _client;

  MediaService(this._client);

  /// 获取海报墙（电影+剧集混合分页）
  Future<ApiResponse<List<MediaItem>>> getPosters({
    int page = 1,
    int pageSize = 20,
  }) async {
    return _client.get<List<MediaItem>>(
      ApiConstants.libraryPosters,
      queryParameters: {
        'page': page,
        'page_size': pageSize,
      },
      fromJson: (json) => (json as List)
          .map((e) => MediaItem.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  // ==================== 电影相关 ====================

  /// 获取电影列表
  Future<ApiResponse<List<Movie>>> getMovies({
    int page = 1,
    int pageSize = 20,
  }) async {
    return _client.get<List<Movie>>(
      ApiConstants.movies,
      queryParameters: {
        'page': page,
        'page_size': pageSize,
      },
      fromJson: (json) => (json as List)
          .map((e) => Movie.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  /// 获取电影详情
  Future<ApiResponse<Movie>> getMovieDetail(int id) async {
    return _client.get<Movie>(
      ApiConstants.movieDetail(id),
      fromJson: (json) => Movie.fromJson(json as Map<String, dynamic>),
    );
  }

  /// 搜索电影
  Future<ApiResponse<List<Movie>>> searchMovies(String query) async {
    return _client.get<List<Movie>>(
      ApiConstants.movieSearch,
      queryParameters: {'q': query},
      fromJson: (json) => (json as List)
          .map((e) => Movie.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  /// 获取电影播放信息
  Future<ApiResponse<StreamInfo>> getMovieStream(int id) async {
    return _client.get<StreamInfo>(
      ApiConstants.movieStream(id),
      fromJson: (json) => StreamInfo.fromJson(json as Map<String, dynamic>),
    );
  }

  /// 重新刮削电影
  Future<ApiResponse<Movie>> scrapeMovie(int id) async {
    return _client.post<Movie>(
      ApiConstants.movieScrape(id),
      fromJson: (json) => Movie.fromJson(json as Map<String, dynamic>),
    );
  }

  /// 删除电影
  Future<ApiResponse<void>> deleteMovie(int id) async {
    return _client.delete(ApiConstants.movieDetail(id));
  }

  // ==================== 剧集相关 ====================

  /// 获取剧集列表
  Future<ApiResponse<List<TvShow>>> getTvShows({
    int page = 1,
    int pageSize = 20,
  }) async {
    return _client.get<List<TvShow>>(
      ApiConstants.tvShows,
      queryParameters: {
        'page': page,
        'page_size': pageSize,
      },
      fromJson: (json) => (json as List)
          .map((e) => TvShow.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  /// 获取剧集详情
  Future<ApiResponse<TvShow>> getTvShowDetail(int id) async {
    return _client.get<TvShow>(
      ApiConstants.tvShowDetail(id),
      fromJson: (json) {
        final data = json as Map<String, dynamic>;
        // API 返回格式: {"tv_show": {...}, "seasons": [{"season": {...}, "episodes": [...]}]}
        final tvShowData = data['tv_show'] as Map<String, dynamic>?;
        final seasonsData = data['seasons'] as List<dynamic>?;

        if (tvShowData == null) {
          throw Exception('Invalid response: tv_show is null');
        }

        // 解析 seasons，将嵌套的 season 对象和 episodes 提取出来
        List<Season>? seasons;
        if (seasonsData != null) {
          seasons = seasonsData.map((item) {
            final seasonItem = item as Map<String, dynamic>;
            final seasonData = seasonItem['season'] as Map<String, dynamic>;
            final episodesData = seasonItem['episodes'] as List<dynamic>?;

            // 将 episodes 注入到 season 数据中
            final seasonWithEpisodes = Map<String, dynamic>.from(seasonData);
            if (episodesData != null) {
              seasonWithEpisodes['episodes'] = episodesData;
            }

            return Season.fromJson(seasonWithEpisodes);
          }).toList();
        }

        // 创建 TvShow 并注入 seasons
        final tvShowWithSeasons = Map<String, dynamic>.from(tvShowData);
        if (seasons != null) {
          tvShowWithSeasons['seasons'] = seasons.map((s) => s.toJson()).toList();
        }

        return TvShow.fromJson(tvShowWithSeasons);
      },
    );
  }

  /// 搜索剧集
  Future<ApiResponse<List<TvShow>>> searchTvShows(String query) async {
    return _client.get<List<TvShow>>(
      ApiConstants.tvShowSearch,
      queryParameters: {'q': query},
      fromJson: (json) => (json as List)
          .map((e) => TvShow.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  /// 获取剧集的所有季
  Future<ApiResponse<List<Season>>> getTvShowSeasons(int tvShowId) async {
    return _client.get<List<Season>>(
      ApiConstants.tvShowSeasons(tvShowId),
      fromJson: (json) => (json as List)
          .map((e) => Season.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  /// 获取某季的所有集
  Future<ApiResponse<List<Episode>>> getSeasonEpisodes(
    int tvShowId,
    int seasonId,
  ) async {
    return _client.get<List<Episode>>(
      ApiConstants.tvShowEpisodes(tvShowId, seasonId),
      fromJson: (json) => (json as List)
          .map((e) => Episode.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  /// 获取剧集播放信息
  Future<ApiResponse<StreamInfo>> getEpisodeStream(
    int tvShowId,
    int seasonId,
    int episodeId,
  ) async {
    return _client.get<StreamInfo>(
      ApiConstants.episodeStream(tvShowId, seasonId, episodeId),
      fromJson: (json) => StreamInfo.fromJson(json as Map<String, dynamic>),
    );
  }

  /// 重新刮削剧集
  Future<ApiResponse<TvShow>> scrapeTvShow(int id) async {
    return _client.post<TvShow>(
      ApiConstants.tvShowScrape(id),
      fromJson: (json) => TvShow.fromJson(json as Map<String, dynamic>),
    );
  }

  /// 删除剧集
  Future<ApiResponse<void>> deleteTvShow(int id) async {
    return _client.delete(ApiConstants.tvShowDetail(id));
  }

  // ==================== 分类相关 ====================

  /// 获取分类统计
  Future<ApiResponse<List<CategoryStats>>> getCategories() async {
    return _client.get<List<CategoryStats>>(
      ApiConstants.libraryCategories,
      fromJson: (json) => (json as List)
          .map((e) => CategoryStats.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  /// 获取分类内容
  Future<ApiResponse<List<MediaItem>>> getCategoryItems(
    String category, {
    int page = 1,
    int pageSize = 20,
  }) async {
    return _client.get<List<MediaItem>>(
      ApiConstants.libraryPosters,
      queryParameters: {
        'category': category,
        'page': page,
        'page_size': pageSize,
      },
      fromJson: (json) => (json as List)
          .map((e) => MediaItem.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  // ==================== 观看历史相关 ====================

  /// 获取最近观看
  Future<ApiResponse<List<WatchHistoryItem>>> getRecentlyWatched({
    int limit = 20,
  }) async {
    return _client.get<List<WatchHistoryItem>>(
      ApiConstants.historyRecent,
      queryParameters: {'limit': limit},
      fromJson: (json) => (json as List)
          .map((e) => WatchHistoryItem.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  /// 更新观看进度
  Future<ApiResponse<void>> updateWatchProgress({
    required String mediaType,
    required int mediaId,
    int? episodeId,
    required int position,
    required int duration,
  }) async {
    return _client.post(
      ApiConstants.historyUpdate,
      data: {
        'media_type': mediaType,
        'media_id': mediaId,
        'episode_id': episodeId ?? 0,
        'position': position,
        'duration': duration,
      },
    );
  }

  /// 获取单个媒体的观看进度
  Future<ApiResponse<WatchHistoryItem>> getWatchProgress(
    String mediaType,
    int mediaId,
  ) async {
    return _client.get<WatchHistoryItem>(
      ApiConstants.historyGet(mediaType, mediaId),
      fromJson: (json) =>
          WatchHistoryItem.fromJson(json as Map<String, dynamic>),
    );
  }
}
