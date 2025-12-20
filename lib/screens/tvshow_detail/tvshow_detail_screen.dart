import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/widgets/loading_widget.dart';
import '../../data/models/models.dart';
import '../../providers/providers.dart';

/// 剧集详情页面
class TvShowDetailScreen extends ConsumerStatefulWidget {
  final int tvShowId;

  const TvShowDetailScreen({super.key, required this.tvShowId});

  @override
  ConsumerState<TvShowDetailScreen> createState() => _TvShowDetailScreenState();
}

class _TvShowDetailScreenState extends ConsumerState<TvShowDetailScreen> {
  int? _selectedSeasonId;

  @override
  Widget build(BuildContext context) {
    final tvShowAsync = ref.watch(tvShowDetailProvider(widget.tvShowId));
    final theme = Theme.of(context);

    return Scaffold(
      body: tvShowAsync.when(
        loading: () => const LoadingWidget(message: '加载中...'),
        error: (error, stack) => AppErrorWidget(
          message: error.toString(),
          onRetry: () => ref.invalidate(tvShowDetailProvider(widget.tvShowId)),
        ),
        data: (tvShow) {
          if (tvShow == null) {
            return const AppErrorWidget(message: '剧集不存在');
          }

          // 默认选中第一季
          if (_selectedSeasonId == null && tvShow.seasons != null && tvShow.seasons!.isNotEmpty) {
            _selectedSeasonId = tvShow.seasons!.first.id;
          }

          return CustomScrollView(
            slivers: [
              // 背景图和标题
              SliverAppBar(
                expandedHeight: 300,
                pinned: true,
                flexibleSpace: FlexibleSpaceBar(
                  title: Text(
                    tvShow.name,
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
                      if (tvShow.backdropPath != null && tvShow.backdropPath!.isNotEmpty)
                        CachedNetworkImage(
                          imageUrl: tvShow.backdropPath!,
                          fit: BoxFit.cover,
                          errorWidget: (context, url, error) =>
                              Container(color: theme.colorScheme.surfaceContainerHighest),
                        )
                      else if (tvShow.posterPath != null && tvShow.posterPath!.isNotEmpty)
                        CachedNetworkImage(
                          imageUrl: tvShow.posterPath!,
                          fit: BoxFit.cover,
                          errorWidget: (context, url, error) =>
                              Container(color: theme.colorScheme.surfaceContainerHighest),
                        )
                      else
                        Container(color: theme.colorScheme.surfaceContainerHighest),
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
                    onPressed: () =>
                        ref.invalidate(tvShowDetailProvider(widget.tvShowId)),
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
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 海报
                          if (tvShow.posterPath != null && tvShow.posterPath!.isNotEmpty)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: CachedNetworkImage(
                                imageUrl: tvShow.posterPath!,
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
                                  child: const Icon(Icons.tv, size: 48),
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
                              child: const Icon(Icons.tv, size: 48),
                            ),
                          const SizedBox(width: 16),
                          // 信息
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (tvShow.originalName != null &&
                                    tvShow.originalName != tvShow.name)
                                  Text(
                                    tvShow.originalName!,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: theme.colorScheme.outline,
                                    ),
                                  ),
                                const SizedBox(height: 8),
                                _buildInfoRow(
                                  Icons.calendar_today,
                                  '${tvShow.year ?? "未知"}',
                                  theme,
                                ),
                                if (tvShow.numberOfSeasons != null)
                                  _buildInfoRow(
                                    Icons.folder,
                                    '${tvShow.numberOfSeasons} 季',
                                    theme,
                                  ),
                                if (tvShow.numberOfEpisodes != null)
                                  _buildInfoRow(
                                    Icons.video_library,
                                    '${tvShow.numberOfEpisodes} 集',
                                    theme,
                                  ),
                                if (tvShow.rating != null && tvShow.rating! > 0)
                                  _buildInfoRow(
                                    Icons.star,
                                    tvShow.rating!.toStringAsFixed(1),
                                    theme,
                                    iconColor: Colors.amber,
                                  ),
                                if (tvShow.status != null)
                                  _buildInfoRow(
                                    Icons.info_outline,
                                    tvShow.statusText,
                                    theme,
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // 简介
                      if (tvShow.overview != null &&
                          tvShow.overview!.isNotEmpty) ...[
                        Text(
                          '简介',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          tvShow.overview!,
                          style: theme.textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 24),
                      ],

                      // 季选择
                      if (tvShow.seasons != null && tvShow.seasons!.isNotEmpty) ...[
                        Text(
                          '选择季',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 40,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: tvShow.seasons!.length,
                            separatorBuilder: (_, __) => const SizedBox(width: 8),
                            itemBuilder: (context, index) {
                              final season = tvShow.seasons![index];
                              final isSelected = season.id == _selectedSeasonId;
                              return ChoiceChip(
                                label: Text(season.displayName),
                                selected: isSelected,
                                onSelected: (selected) {
                                  if (selected) {
                                    setState(() {
                                      _selectedSeasonId = season.id;
                                    });
                                  }
                                },
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ],
                  ),
                ),
              ),

              // 剧集列表
              if (_selectedSeasonId != null)
                _EpisodesList(
                  tvShowId: widget.tvShowId,
                  seasonId: _selectedSeasonId!,
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

/// 剧集列表组件
class _EpisodesList extends ConsumerWidget {
  final int tvShowId;
  final int seasonId;

  const _EpisodesList({
    required this.tvShowId,
    required this.seasonId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final episodesAsync = ref.watch(
      seasonEpisodesProvider((tvShowId: tvShowId, seasonId: seasonId)),
    );

    return episodesAsync.when(
      loading: () => const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (error, stack) => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('加载失败: $error'),
        ),
      ),
      data: (episodes) {
        if (episodes == null || episodes.isEmpty) {
          return const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: Text('暂无剧集')),
            ),
          );
        }

        return SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final episode = episodes[index];
              return _EpisodeCard(
                episode: episode,
                tvShowId: tvShowId,
                seasonId: seasonId,
              );
            },
            childCount: episodes.length,
          ),
        );
      },
    );
  }
}

/// 单集卡片
class _EpisodeCard extends StatelessWidget {
  final Episode episode;
  final int tvShowId;
  final int seasonId;

  const _EpisodeCard({
    required this.episode,
    required this.tvShowId,
    required this.seasonId,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: InkWell(
        onTap: episode.hasFile
            ? () => context.push(
                  '/player/episode/$tvShowId/$seasonId/${episode.id}',
                )
            : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // 缩略图
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: episode.stillPath != null && episode.stillPath!.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: episode.stillPath!,
                        width: 120,
                        height: 68,
                        fit: BoxFit.cover,
                        errorWidget: (context, url, error) => Container(
                          width: 120,
                          height: 68,
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: const Icon(Icons.play_circle_outline),
                        ),
                      )
                    : Container(
                        width: 120,
                        height: 68,
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: const Icon(Icons.play_circle_outline),
                      ),
              ),
              const SizedBox(width: 12),
              // 信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      episode.displayTitle,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    if (episode.overview != null && episode.overview!.isNotEmpty)
                      Text(
                        episode.overview!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (episode.runtime != null) ...[
                          Icon(
                            Icons.access_time,
                            size: 12,
                            color: theme.colorScheme.outline,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            episode.formattedRuntime,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                          const SizedBox(width: 12),
                        ],
                        if (!episode.hasFile)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.errorContainer,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '无文件',
                              style: TextStyle(
                                fontSize: 10,
                                color: theme.colorScheme.error,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              // 播放按钮
              if (episode.hasFile)
                Icon(
                  Icons.play_circle_filled,
                  color: theme.colorScheme.primary,
                  size: 32,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
