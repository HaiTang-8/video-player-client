import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../data/models/models.dart';
import '../../../providers/download_provider.dart';
import '../../../providers/media_provider.dart';
import 'library_poster_card.dart';
import 'media_poster_row.dart';

class LocalMediaRow extends ConsumerWidget {
  const LocalMediaRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(downloadManagerProvider);
    final completedTasks = state.completedTasks;

    if (completedTasks.isEmpty) {
      return const SizedBox.shrink();
    }

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

    return MediaPosterRow(
      title: '本地影片',
      count: tasks.length,
      onTitleTap: () => context.push('/downloads'),
      itemCount: tasks.length,
      itemBuilder: (index, width) => _LocalMediaCardWrapper(
        key: ValueKey('local_${tasks[index].id}'),
        task: tasks[index],
        width: width,
      ),
      itemKeyPrefix: 'local',
    );
  }
}

class _LocalMediaCardWrapper extends ConsumerWidget {
  final DownloadTask task;
  final double width;

  const _LocalMediaCardWrapper({
    super.key,
    required this.task,
    required this.width,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (task.isMovie && task.movieId != null) {
      return _MovieCardWrapper(movieId: task.movieId!, width: width);
    } else if (task.isEpisode && task.tvShowId != null) {
      return _TvShowCardWrapper(tvShowId: task.tvShowId!, width: width);
    }
    return SizedBox(width: width);
  }
}

class _MovieCardWrapper extends ConsumerWidget {
  final int movieId;
  final double width;

  const _MovieCardWrapper({required this.movieId, required this.width});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final movieAsync = ref.watch(movieDetailProvider(movieId));

    return movieAsync.when(
      data: (movie) {
        if (movie == null) return SizedBox(width: width);
        final item = MediaItem(
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
        );
        return LibraryPosterCard(
          item: item,
          width: width,
          onTap: () => context.push('/movie/$movieId'),
        );
      },
      loading: () => _buildPlaceholder(context),
      error: (_, _) => _buildPlaceholder(context),
    );
  }

  Widget _buildPlaceholder(BuildContext context) {
    final theme = Theme.of(context);
    final height = width / 0.48;
    return SizedBox(
      width: width,
      height: height,
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
    );
  }
}

class _TvShowCardWrapper extends ConsumerWidget {
  final int tvShowId;
  final double width;

  const _TvShowCardWrapper({required this.tvShowId, required this.width});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tvShowAsync = ref.watch(tvShowDetailProvider(tvShowId));

    return tvShowAsync.when(
      data: (tvShow) {
        if (tvShow == null) return SizedBox(width: width);
        final item = MediaItem(
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
        );
        return LibraryPosterCard(
          item: item,
          width: width,
          onTap: () => context.push('/tvshow/$tvShowId'),
        );
      },
      loading: () => _buildPlaceholder(context),
      error: (_, _) => _buildPlaceholder(context),
    );
  }

  Widget _buildPlaceholder(BuildContext context) {
    final theme = Theme.of(context);
    final height = width / 0.48;
    return SizedBox(
      width: width,
      height: height,
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
    );
  }
}
