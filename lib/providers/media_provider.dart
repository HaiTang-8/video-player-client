import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/models.dart';
import '../data/services/api_client.dart';
import '../data/services/media_service.dart';
import 'server_provider.dart';

/// MediaService Provider
final mediaServiceProvider = Provider<MediaService?>((ref) {
  final client = ref.watch(apiClientProvider);
  if (client == null) return null;
  return MediaService(client);
});

/// 海报墙数据状态
class PostersState {
  final List<MediaItem> items;
  final bool isLoading;
  final bool hasMore;
  final int currentPage;
  final String? error;

  PostersState({
    this.items = const [],
    this.isLoading = false,
    this.hasMore = true,
    this.currentPage = 0,
    this.error,
  });

  PostersState copyWith({
    List<MediaItem>? items,
    bool? isLoading,
    bool? hasMore,
    int? currentPage,
    String? error,
  }) {
    return PostersState(
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      hasMore: hasMore ?? this.hasMore,
      currentPage: currentPage ?? this.currentPage,
      error: error,
    );
  }
}

/// 海报墙 Provider
final postersProvider =
    StateNotifierProvider<PostersNotifier, PostersState>((ref) {
  final service = ref.watch(mediaServiceProvider);
  return PostersNotifier(service);
});

class PostersNotifier extends StateNotifier<PostersState> {
  final MediaService? _service;

  PostersNotifier(this._service) : super(PostersState());

  /// 加载第一页
  Future<void> loadPosters() async {
    if (_service == null) return;
    if (state.isLoading) return;

    state = state.copyWith(isLoading: true, error: null);

    final response = await _service.getPosters(page: 1);

    if (response.isSuccess && response.data != null) {
      state = state.copyWith(
        items: response.data!,
        isLoading: false,
        currentPage: 1,
        hasMore: response.data!.length >= 20,
      );
    } else {
      state = state.copyWith(
        isLoading: false,
        error: response.error,
      );
    }
  }

  /// 加载更多
  Future<void> loadMore() async {
    if (_service == null) return;
    if (state.isLoading || !state.hasMore) return;

    state = state.copyWith(isLoading: true);

    final nextPage = state.currentPage + 1;
    final response = await _service.getPosters(page: nextPage);

    if (response.isSuccess && response.data != null) {
      state = state.copyWith(
        items: [...state.items, ...response.data!],
        isLoading: false,
        currentPage: nextPage,
        hasMore: response.data!.length >= 20,
      );
    } else {
      state = state.copyWith(
        isLoading: false,
        error: response.error,
      );
    }
  }

  /// 刷新
  Future<void> refresh() async {
    state = PostersState();
    await loadPosters();
  }
}

/// 电影详情 Provider
final movieDetailProvider =
    FutureProvider.family<Movie?, int>((ref, id) async {
  final service = ref.watch(mediaServiceProvider);
  if (service == null) return null;

  final response = await service.getMovieDetail(id);
  return response.data;
});

/// 剧集详情 Provider
final tvShowDetailProvider =
    FutureProvider.family<TvShow?, int>((ref, id) async {
  final service = ref.watch(mediaServiceProvider);
  if (service == null) return null;

  final response = await service.getTvShowDetail(id);
  return response.data;
});

/// 季的剧集列表 Provider
final seasonEpisodesProvider =
    FutureProvider.family<List<Episode>?, ({int tvShowId, int seasonId})>(
        (ref, params) async {
  final service = ref.watch(mediaServiceProvider);
  if (service == null) return null;

  final response =
      await service.getSeasonEpisodes(params.tvShowId, params.seasonId);
  return response.data;
});

/// 电影播放信息 Provider
final movieStreamProvider =
    FutureProvider.family<StreamInfo?, int>((ref, id) async {
  final service = ref.watch(mediaServiceProvider);
  if (service == null) return null;

  final response = await service.getMovieStream(id);
  return response.data;
});

/// 剧集播放信息 Provider
final episodeStreamProvider = FutureProvider.family<StreamInfo?,
    ({int tvShowId, int seasonId, int episodeId})>((ref, params) async {
  final service = ref.watch(mediaServiceProvider);
  if (service == null) return null;

  final response = await service.getEpisodeStream(
    params.tvShowId,
    params.seasonId,
    params.episodeId,
  );
  return response.data;
});

/// 搜索状态
class SearchState {
  final List<Movie> movies;
  final List<TvShow> tvShows;
  final bool isLoading;
  final String? error;
  final String query;

  SearchState({
    this.movies = const [],
    this.tvShows = const [],
    this.isLoading = false,
    this.error,
    this.query = '',
  });

  SearchState copyWith({
    List<Movie>? movies,
    List<TvShow>? tvShows,
    bool? isLoading,
    String? error,
    String? query,
  }) {
    return SearchState(
      movies: movies ?? this.movies,
      tvShows: tvShows ?? this.tvShows,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      query: query ?? this.query,
    );
  }
}

/// 搜索 Provider
final searchProvider =
    StateNotifierProvider<SearchNotifier, SearchState>((ref) {
  final service = ref.watch(mediaServiceProvider);
  return SearchNotifier(service);
});

class SearchNotifier extends StateNotifier<SearchState> {
  final MediaService? _service;

  SearchNotifier(this._service) : super(SearchState());

  /// 执行搜索
  Future<void> search(String query) async {
    if (_service == null) return;
    if (query.isEmpty) {
      state = SearchState();
      return;
    }

    state = state.copyWith(isLoading: true, query: query, error: null);

    // 并行搜索电影和剧集
    final results = await Future.wait([
      _service.searchMovies(query),
      _service.searchTvShows(query),
    ]);

    final movieResponse = results[0] as ApiResponse<List<Movie>>;
    final tvShowResponse = results[1] as ApiResponse<List<TvShow>>;

    state = state.copyWith(
      movies: movieResponse.data ?? [],
      tvShows: tvShowResponse.data ?? [],
      isLoading: false,
      error: movieResponse.error ?? tvShowResponse.error,
    );
  }

  /// 清空搜索
  void clear() {
    state = SearchState();
  }
}
