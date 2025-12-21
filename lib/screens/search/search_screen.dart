import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/widgets/app_back_button.dart';
import '../../core/widgets/desktop_title_bar.dart';
import '../../core/window/window_controls.dart';
import '../../core/widgets/loading_widget.dart';
import '../../data/models/models.dart';
import '../../providers/providers.dart';

/// 搜索页面
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _searchController = TextEditingController();
  Timer? _debounceTimer;

  @override
  void dispose() {
    _searchController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      ref.read(searchProvider.notifier).search(query);
    });
  }

  @override
  Widget build(BuildContext context) {
    final searchState = ref.watch(searchProvider);
    final theme = Theme.of(context);
    final isDesktop = WindowControls.isDesktop;

    return Scaffold(
      appBar:
          isDesktop
              ? DesktopTitleBar(
                leading: AppBackButton(onPressed: () => context.pop()),
                centerTitle: false,
                titleInteractive: true,
                title: SizedBox(
                  width: 420,
                  child: TextField(
                    controller: _searchController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: '搜索电影、剧集...',
                      border: InputBorder.none,
                      filled: false,
                    ),
                    onChanged: _onSearchChanged,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (query) {
                      ref.read(searchProvider.notifier).search(query);
                    },
                  ),
                ),
                actions: [
                  if (_searchController.text.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        ref.read(searchProvider.notifier).clear();
                      },
                    ),
                ],
              )
              : AppBar(
                centerTitle: false,
                automaticallyImplyLeading: false,
                leadingWidth: kAppBackButtonWidth,
                titleSpacing: 1,
                leading: AppBackButton(onPressed: () => context.pop()),
                title: TextField(
                  controller: _searchController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: '搜索电影、剧集...',
                    border: InputBorder.none,
                    filled: false,
                  ),
                  onChanged: _onSearchChanged,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (query) {
                    ref.read(searchProvider.notifier).search(query);
                  },
                ),
                actions: [
                  if (_searchController.text.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        ref.read(searchProvider.notifier).clear();
                      },
                    ),
                ],
              ),
      body: _buildBody(searchState, theme),
    );
  }

  Widget _buildBody(SearchState state, ThemeData theme) {
    if (state.query.isEmpty) {
      return const EmptyWidget(message: '输入关键词搜索电影或剧集', icon: Icons.search);
    }

    if (state.isLoading) {
      return const LoadingWidget(message: '搜索中...');
    }

    if (state.error != null) {
      return AppErrorWidget(
        message: state.error!,
        onRetry: () => ref.read(searchProvider.notifier).search(state.query),
      );
    }

    if (state.movies.isEmpty && state.tvShows.isEmpty) {
      return const EmptyWidget(message: '未找到相关内容', icon: Icons.search_off);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 电影结果
        if (state.movies.isNotEmpty) ...[
          Text(
            '电影 (${state.movies.length})',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          ...state.movies.map((movie) => _MovieSearchItem(movie: movie)),
          const SizedBox(height: 24),
        ],

        // 剧集结果
        if (state.tvShows.isNotEmpty) ...[
          Text(
            '剧集 (${state.tvShows.length})',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          ...state.tvShows.map((tvShow) => _TvShowSearchItem(tvShow: tvShow)),
        ],
      ],
    );
  }
}

/// 电影搜索结果项
class _MovieSearchItem extends StatelessWidget {
  final Movie movie;

  const _MovieSearchItem({required this.movie});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => context.push('/movie/${movie.id}'),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // 海报
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child:
                    movie.posterPath != null && movie.posterPath!.isNotEmpty
                        ? CachedNetworkImage(
                          imageUrl: movie.posterPath!,
                          width: 60,
                          height: 90,
                          fit: BoxFit.cover,
                          errorWidget:
                              (context, url, error) => Container(
                                width: 60,
                                height: 90,
                                color:
                                    theme.colorScheme.surfaceContainerHighest,
                                child: const Icon(Icons.movie),
                              ),
                        )
                        : Container(
                          width: 60,
                          height: 90,
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: const Icon(Icons.movie),
                        ),
              ),
              const SizedBox(width: 12),
              // 信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      movie.title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (movie.year != null) ...[
                          Text(
                            '${movie.year}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        if (movie.rating != null && movie.rating! > 0) ...[
                          const Icon(Icons.star, size: 14, color: Colors.amber),
                          const SizedBox(width: 2),
                          Text(
                            movie.rating!.toStringAsFixed(1),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (movie.overview != null &&
                        movie.overview!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        movie.overview!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

/// 剧集搜索结果项
class _TvShowSearchItem extends StatelessWidget {
  final TvShow tvShow;

  const _TvShowSearchItem({required this.tvShow});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => context.push('/tvshow/${tvShow.id}'),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // 海报
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child:
                    tvShow.posterPath != null && tvShow.posterPath!.isNotEmpty
                        ? CachedNetworkImage(
                          imageUrl: tvShow.posterPath!,
                          width: 60,
                          height: 90,
                          fit: BoxFit.cover,
                          errorWidget:
                              (context, url, error) => Container(
                                width: 60,
                                height: 90,
                                color:
                                    theme.colorScheme.surfaceContainerHighest,
                                child: const Icon(Icons.tv),
                              ),
                        )
                        : Container(
                          width: 60,
                          height: 90,
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: const Icon(Icons.tv),
                        ),
              ),
              const SizedBox(width: 12),
              // 信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tvShow.name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (tvShow.year != null) ...[
                          Text(
                            '${tvShow.year}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        if (tvShow.numberOfSeasons != null) ...[
                          Text(
                            '${tvShow.numberOfSeasons}季',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        if (tvShow.rating != null && tvShow.rating! > 0) ...[
                          const Icon(Icons.star, size: 14, color: Colors.amber),
                          const SizedBox(width: 2),
                          Text(
                            tvShow.rating!.toStringAsFixed(1),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (tvShow.overview != null &&
                        tvShow.overview!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        tvShow.overview!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
