import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/widgets/loading_widget.dart';
import '../../providers/providers.dart';

/// 电影详情页面
class MovieDetailScreen extends ConsumerWidget {
  final int movieId;

  const MovieDetailScreen({super.key, required this.movieId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final movieAsync = ref.watch(movieDetailProvider(movieId));
    final theme = Theme.of(context);

    return Scaffold(
      body: movieAsync.when(
        loading: () => const LoadingWidget(message: '加载中...'),
        error: (error, stack) => AppErrorWidget(
          message: error.toString(),
          onRetry: () => ref.invalidate(movieDetailProvider(movieId)),
        ),
        data: (movie) {
          if (movie == null) {
            return const AppErrorWidget(message: '电影不存在');
          }

          return CustomScrollView(
            slivers: [
              // 背景图和标题
              SliverAppBar(
                expandedHeight: 300,
                pinned: true,
                flexibleSpace: FlexibleSpaceBar(
                  title: Text(
                    movie.title,
                    style: const TextStyle(
                      shadows: [
                        Shadow(
                          blurRadius: 10,
                          color: Colors.black,
                        ),
                      ],
                    ),
                  ),
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (movie.backdropPath != null && movie.backdropPath!.isNotEmpty)
                        CachedNetworkImage(
                          imageUrl: movie.backdropPath!,
                          fit: BoxFit.cover,
                          errorWidget: (context, url, error) =>
                              Container(color: theme.colorScheme.surfaceContainerHighest),
                        )
                      else if (movie.posterPath != null && movie.posterPath!.isNotEmpty)
                        CachedNetworkImage(
                          imageUrl: movie.posterPath!,
                          fit: BoxFit.cover,
                          errorWidget: (context, url, error) =>
                              Container(color: theme.colorScheme.surfaceContainerHighest),
                        )
                      else
                        Container(color: theme.colorScheme.surfaceContainerHighest),
                      // 渐变遮罩
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.7),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: () => ref.invalidate(movieDetailProvider(movieId)),
                  ),
                ],
              ),

              // 详情内容
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 基本信息行
                      Row(
                        children: [
                          // 海报
                          if (movie.posterPath != null && movie.posterPath!.isNotEmpty)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: CachedNetworkImage(
                                imageUrl: movie.posterPath!,
                                width: 120,
                                height: 180,
                                fit: BoxFit.cover,
                                errorWidget: (context, url, error) => Container(
                                  width: 120,
                                  height: 180,
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(Icons.movie, size: 48),
                                ),
                              ),
                            )
                          else
                            Container(
                              width: 120,
                              height: 180,
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.movie, size: 48),
                            ),
                          const SizedBox(width: 16),
                          // 信息
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (movie.originalTitle != null &&
                                    movie.originalTitle != movie.title)
                                  Text(
                                    movie.originalTitle!,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: theme.colorScheme.outline,
                                    ),
                                  ),
                                const SizedBox(height: 8),
                                _buildInfoRow(
                                  Icons.calendar_today,
                                  '${movie.year ?? "未知"}',
                                  theme,
                                ),
                                if (movie.runtime != null)
                                  _buildInfoRow(
                                    Icons.access_time,
                                    movie.formattedRuntime,
                                    theme,
                                  ),
                                if (movie.rating != null && movie.rating! > 0)
                                  _buildInfoRow(
                                    Icons.star,
                                    movie.rating!.toStringAsFixed(1),
                                    theme,
                                    iconColor: Colors.amber,
                                  ),
                                if (movie.fileSize != null)
                                  _buildInfoRow(
                                    Icons.storage,
                                    movie.formattedFileSize,
                                    theme,
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // 播放按钮
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () => context.push('/player/movie/$movieId'),
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('播放'),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // 简介
                      if (movie.overview != null &&
                          movie.overview!.isNotEmpty) ...[
                        Text(
                          '简介',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          movie.overview!,
                          style: theme.textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 24),
                      ],

                      // 类型标签
                      if (movie.genres != null && movie.genres!.isNotEmpty) ...[
                        Text(
                          '类型',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: movie.genres!
                              .map((genre) => Chip(label: Text(genre)))
                              .toList(),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildInfoRow(
    IconData icon,
    String text,
    ThemeData theme, {
    Color? iconColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: iconColor ?? theme.colorScheme.outline,
          ),
          const SizedBox(width: 8),
          Text(
            text,
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}
