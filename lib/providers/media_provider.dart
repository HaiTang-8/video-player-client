import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/models.dart';
import '../data/services/media_service.dart';
import 'server_provider.dart';

final mediaServiceProvider = Provider<MediaService?>((ref) {
  final client = ref.watch(apiClientProvider);
  if (client == null) return null;
  return MediaService(client);
});

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

final postersProvider = NotifierProvider<PostersNotifier, PostersState>(
  PostersNotifier.new,
);

class PostersNotifier extends Notifier<PostersState> {
  @override
  PostersState build() => PostersState();

  Future<void> loadPosters() async {
    final service = ref.read(mediaServiceProvider);
    if (service == null) return;
    if (state.isLoading) return;

    state = state.copyWith(isLoading: true, error: null);

    final response = await service.getPosters(page: 1);

    if (response.isSuccess && response.data != null) {
      state = state.copyWith(
        items: response.data!,
        isLoading: false,
        currentPage: 1,
        hasMore: response.data!.length >= 20,
      );
    } else {
      state = state.copyWith(isLoading: false, error: response.error);
    }
  }

  Future<void> loadMore() async {
    final service = ref.read(mediaServiceProvider);
    if (service == null) return;
    if (state.isLoading || !state.hasMore) return;

    state = state.copyWith(isLoading: true);

    final nextPage = state.currentPage + 1;
    final response = await service.getPosters(page: nextPage);

    if (response.isSuccess && response.data != null) {
      state = state.copyWith(
        items: [...state.items, ...response.data!],
        isLoading: false,
        currentPage: nextPage,
        hasMore: response.data!.length >= 20,
      );
    } else {
      state = state.copyWith(isLoading: false, error: response.error);
    }
  }

  Future<void> refresh() async {
    state = PostersState();
    await loadPosters();
  }
}

final movieDetailProvider = FutureProvider.family<Movie?, int>((ref, id) async {
  final service = ref.watch(mediaServiceProvider);
  if (service == null) return null;
  final response = await service.getMovieDetail(id);
  return response.data;
});

final tvShowDetailProvider = FutureProvider.family<TvShow?, int>((
  ref,
  id,
) async {
  final service = ref.watch(mediaServiceProvider);
  if (service == null) return null;
  final response = await service.getTvShowDetail(id);
  return response.data;
});

final seasonEpisodesProvider =
    FutureProvider.family<List<Episode>?, ({int tvShowId, int seasonId})>((
      ref,
      params,
    ) async {
      final service = ref.watch(mediaServiceProvider);
      if (service == null) return null;
      final response = await service.getSeasonEpisodes(
        params.tvShowId,
        params.seasonId,
      );
      return response.data;
    });

final seasonEpisodeProgressesProvider = FutureProvider.family<
  List<WatchHistoryItem>?,
  ({int tvShowId, int seasonId, int? tmdbId})
>((ref, params) async {
  final service = ref.watch(mediaServiceProvider);
  if (service == null) return null;
  final response = await service.getSeasonEpisodeProgresses(
    tvShowId: params.tvShowId,
    seasonId: params.seasonId,
    tmdbId: params.tmdbId,
  );
  return response.data;
});

final movieStreamProvider = FutureProvider.family<StreamInfo?, int>((
  ref,
  id,
) async {
  final service = ref.watch(mediaServiceProvider);
  if (service == null) return null;
  final response = await service.getMovieStream(id);
  return response.data;
});

final episodeStreamProvider = FutureProvider.family<
  StreamInfo?,
  ({int tvShowId, int seasonId, int episodeId})
>((ref, params) async {
  final service = ref.watch(mediaServiceProvider);
  if (service == null) return null;
  final response = await service.getEpisodeStream(
    params.tvShowId,
    params.seasonId,
    params.episodeId,
  );
  return response.data;
});

final seasonSourceGroupsProvider =
    FutureProvider.family<List<SourceGroup>?, ({int tvShowId, int seasonId})>((
      ref,
      params,
    ) async {
      final service = ref.watch(mediaServiceProvider);
      if (service == null) return null;
      final response = await service.getSeasonSourceGroups(
        params.tvShowId,
        params.seasonId,
      );
      return response.data;
    });

class SearchState {
  final List<MediaItem> items;
  final bool isLoading;
  final bool isLoadingMore;
  final String? error;
  final String query;
  final String category;
  final String sort;
  final String genre;
  final String region;
  final String year;
  final int currentPage;
  final bool hasMore;

  SearchState({
    this.items = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.error,
    this.query = '',
    this.category = '全部',
    this.sort = 'updated',
    this.genre = '类型',
    this.region = '地区',
    this.year = '年份',
    this.currentPage = 0,
    this.hasMore = true,
  });

  SearchState copyWith({
    List<MediaItem>? items,
    bool? isLoading,
    bool? isLoadingMore,
    String? error,
    String? query,
    String? category,
    String? sort,
    String? genre,
    String? region,
    String? year,
    int? currentPage,
    bool? hasMore,
  }) {
    return SearchState(
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      error: error,
      query: query ?? this.query,
      category: category ?? this.category,
      sort: sort ?? this.sort,
      genre: genre ?? this.genre,
      region: region ?? this.region,
      year: year ?? this.year,
      currentPage: currentPage ?? this.currentPage,
      hasMore: hasMore ?? this.hasMore,
    );
  }

  List<Movie> get movies =>
      items
          .where((item) => item.type == MediaType.movie)
          .map(
            (item) => Movie(
              id: item.id,
              title: item.title,
              posterPath: item.posterPath,
              backdropPath: item.backdropPath,
              rating: item.rating,
              year: item.year,
            ),
          )
          .toList();

  List<TvShow> get tvShows =>
      items
          .where((item) => item.type == MediaType.tvshow)
          .map(
            (item) => TvShow(
              id: item.id,
              name: item.title,
              posterPath: item.posterPath,
              backdropPath: item.backdropPath,
              rating: item.rating,
              year: item.year,
            ),
          )
          .toList();
}

final searchProvider = NotifierProvider<SearchNotifier, SearchState>(
  SearchNotifier.new,
);

class SearchNotifier extends Notifier<SearchState> {
  @override
  SearchState build() => SearchState();

  Future<void> search(String query) async {
    final service = ref.read(mediaServiceProvider);
    if (service == null) return;

    state = state.copyWith(
      isLoading: true,
      query: query,
      error: null,
      currentPage: 1,
      hasMore: true,
    );

    final response = await service.search(
      query: query,
      category: state.category,
      sort: _mapSort(state.sort),
      genre: state.genre,
      region: state.region,
      year: state.year,
      page: 1,
    );

    state = state.copyWith(
      items: response.data ?? [],
      isLoading: false,
      error: response.error,
      hasMore: (response.data?.length ?? 0) >= 20,
    );
  }

  Future<void> loadMore() async {
    final service = ref.read(mediaServiceProvider);
    if (service == null ||
        state.isLoading ||
        state.isLoadingMore ||
        !state.hasMore) {
      return;
    }

    state = state.copyWith(isLoadingMore: true);
    final nextPage = state.currentPage + 1;

    final response = await service.search(
      query: state.query,
      category: state.category,
      sort: _mapSort(state.sort),
      genre: state.genre,
      region: state.region,
      year: state.year,
      page: nextPage,
    );

    state = state.copyWith(
      items: [...state.items, ...response.data ?? []],
      isLoadingMore: false,
      currentPage: nextPage,
      hasMore: (response.data?.length ?? 0) >= 20,
      error: response.error,
    );
  }

  Future<void> updateFilters({
    String? query,
    String? category,
    String? sort,
    String? genre,
    String? region,
    String? year,
  }) async {
    state = state.copyWith(
      query: query,
      category: category,
      sort: sort,
      genre: genre,
      region: region,
      year: year,
    );
    await search(state.query);
  }

  String _mapSort(String sort) {
    switch (sort) {
      case '最新更新':
        return 'updated';
      case '最新上映':
        return 'released';
      case '影片评分':
        return 'rating';
      default:
        return 'updated';
    }
  }

  void clear() {
    state = SearchState();
  }
}
