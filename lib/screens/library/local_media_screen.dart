import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/widgets/desktop_app_bar.dart';
import '../../core/widgets/mobile_app_bar.dart';
import '../../core/widgets/smooth_scroll_behavior.dart';
import '../../core/window/window_controls.dart';
import '../../data/models/models.dart';
import '../../providers/download_provider.dart';
import '../../providers/media_provider.dart';
import 'widgets/library_poster_card.dart';

class LocalMediaScreen extends ConsumerWidget {
  const LocalMediaScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(downloadManagerProvider);
    final completedTasks = state.completedTasks;

    final uniqueItems = <String, DownloadTask>{};
    for (final task in completedTasks) {
      final key = task.isMovie
          ? 'movie_${task.movieId}'
          : 'tv_${task.tvShowId}';
      if (!uniqueItems.containsKey(key)) {
        uniqueItems[key] = task;
      }
    }
    final tasks = uniqueItems.values.toList();
    final isDesktop = WindowControls.isDesktop;

    return Scaffold(
      appBar: isDesktop
          ? DesktopAppBar(
              title: const Text('本地影片'),
              onBack: () => context.pop(),
            )
          : MobileAppBar(
              title: const Text('本地影片'),
              onBack: () => context.pop(),
            ),
      body: tasks.isEmpty
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.download_done_outlined, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('暂无本地影片', style: TextStyle(color: Colors.grey)),
                ],
              ),
            )
          : DesktopSmoothScroll(
              child: GridView.builder(
                primary: true,
                clipBehavior: Clip.none,
                padding: EdgeInsets.all(isDesktop ? 24 : 16),
                gridDelegate: isDesktop
                    ? const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 160.0,
                        childAspectRatio: 0.48,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                      )
                    : const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        childAspectRatio: 0.48,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                      ),
                itemCount: tasks.length,
                itemBuilder: (context, index) {
                  final task = tasks[index];
                  return _LocalMediaGridItem(
                    key: ValueKey(task.isMovie
                        ? 'movie_${task.movieId}'
                        : 'tv_${task.tvShowId}'),
                    task: task,
                    isDesktop: isDesktop,
                  );
                },
              ),
            ),
    );
  }
}

class _LocalMediaGridItem extends ConsumerWidget {
  final DownloadTask task;
  final bool isDesktop;

  const _LocalMediaGridItem({
    super.key,
    required this.task,
    required this.isDesktop,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (task.isMovie && task.movieId != null) {
      return _MovieGridItem(task: task, isDesktop: isDesktop);
    } else if (task.isEpisode && task.tvShowId != null) {
      return _TvShowGridItem(task: task, isDesktop: isDesktop);
    }
    return const SizedBox.shrink();
  }
}

class _MovieGridItem extends ConsumerWidget {
  final DownloadTask task;
  final bool isDesktop;

  const _MovieGridItem({required this.task, required this.isDesktop});

  int get movieId => task.movieId!;

  MediaItem _fallbackItem() => MediaItem(
    id: movieId,
    type: MediaType.movie,
    title: task.movieTitle ?? '未知电影',
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final movieAsync = ref.watch(movieDetailProvider(movieId));

    return movieAsync.when(
      data: (movie) {
        final item = movie != null
            ? MediaItem(
                id: movie.id,
                type: MediaType.movie,
                title: movie.title,
                originalTitle: movie.originalTitle,
                posterPath: movie.posterPath,
                backdropPath: movie.backdropPath,
                overview: movie.overview,
                rating: movie.rating,
                year: movie.year,
                releaseDate: movie.releaseDate,
              )
            : _fallbackItem();
        return LibraryPosterCard(
          item: item,
          width: isDesktop ? 140.0 : double.infinity,
          onTap: () => context.push('/movie/$movieId'),
        );
      },
      loading: () => _buildPlaceholder(context),
      error: (_, _) => LibraryPosterCard(
        item: _fallbackItem(),
        width: isDesktop ? 140.0 : double.infinity,
        onTap: () => context.push('/movie/$movieId'),
      ),
    );
  }

  Widget _buildPlaceholder(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
    );
  }
}

class _TvShowGridItem extends ConsumerWidget {
  final DownloadTask task;
  final bool isDesktop;

  const _TvShowGridItem({required this.task, required this.isDesktop});

  int get tvShowId => task.tvShowId!;

  MediaItem _fallbackItem() => MediaItem(
    id: tvShowId,
    type: MediaType.tvshow,
    title: task.tvShowName ?? '未知剧集',
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tvShowAsync = ref.watch(tvShowDetailProvider(tvShowId));

    return tvShowAsync.when(
      data: (tvShow) {
        final item = tvShow != null
            ? MediaItem(
                id: tvShow.id,
                type: MediaType.tvshow,
                title: tvShow.name,
                originalTitle: tvShow.originalName,
                posterPath: tvShow.posterPath,
                backdropPath: tvShow.backdropPath,
                overview: tvShow.overview,
                rating: tvShow.rating,
                year: tvShow.year,
                releaseDate: tvShow.firstAirDate,
                numberOfSeasons: tvShow.numberOfSeasons,
              )
            : _fallbackItem();
        return LibraryPosterCard(
          item: item,
          width: isDesktop ? 140.0 : double.infinity,
          onTap: () => context.push('/tvshow/$tvShowId'),
        );
      },
      loading: () => _buildPlaceholder(context),
      error: (_, _) => LibraryPosterCard(
        item: _fallbackItem(),
        width: isDesktop ? 140.0 : double.infinity,
        onTap: () => context.push('/tvshow/$tvShowId'),
      ),
    );
  }

  Widget _buildPlaceholder(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
    );
  }
}
