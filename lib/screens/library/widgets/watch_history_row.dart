import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/widgets/tap_feedback.dart';
import '../../../core/window/window_controls.dart';
import '../../../data/models/models.dart';
import '../../../core/utils/image_proxy.dart';
import '../../../providers/providers.dart';

/// 最近观看行组件
class WatchHistoryRow extends ConsumerStatefulWidget {
  const WatchHistoryRow({super.key});

  @override
  ConsumerState<WatchHistoryRow> createState() => _WatchHistoryRowState();
}

class _WatchHistoryRowState extends ConsumerState<WatchHistoryRow> {
  static const double _mobileItemWidth = 220.0;
  static const double _desktopMinItemWidth = 220.0;
  static const double _itemSpacing = 16.0;
  static const double _horizontalPadding = 16.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(watchHistoryProvider);
    // 客户端「最近观看」不需要合并模式：按记录逐条展示
    final groups = state.groupedItems(mergeEpisodes: false);

    // 无数据时不显示
    if (!state.isLoading && groups.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: TapFeedback(
            onTap: () => context.push('/watch-history'),
            borderRadius: BorderRadius.circular(8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '最近观看',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  // 显示卡片数量（不合并时等于观看记录条数）
                  '${groups.length}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: theme.colorScheme.outline,
                ),
              ],
            ),
          ),
        ),
        _buildContent(theme, state, groups),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildContent(
    ThemeData theme,
    WatchHistoryState state,
    List<WatchHistoryGroup> groups,
  ) {
    final textScaler = MediaQuery.textScalerOf(context);
    // 图片高度 (220 * 9/16 ≈ 124) + 间距 8 + 文字区域 (标题2行 + 间距2 + 副标题1行)
    final mobileListHeight = 124 + 8 + textScaler.scale(60);

    if (state.isLoading && state.items.isEmpty) {
      return SizedBox(
        height: mobileListHeight,
        child: const Center(child: CircularProgressIndicator()),
      );
    }
    if (state.error != null && state.items.isEmpty) {
      return SizedBox(
        height: mobileListHeight,
        child: Center(
          child: Text('加载失败', style: TextStyle(color: theme.colorScheme.error)),
        ),
      );
    }

    if (!WindowControls.isDesktop) {
      return _buildMobileList(groups);
    }
    return _buildDesktopList(groups);
  }

  Widget _buildMobileList(List<WatchHistoryGroup> groups) {
    final textScaler = MediaQuery.textScalerOf(context);
    // 图片高度 (220 * 9/16 ≈ 124) + 间距 8 + 文字区域 (标题2行 + 间距2 + 副标题1行)
    final listHeight = 124 + 8 + textScaler.scale(60);

    return SizedBox(
      height: listHeight,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: _horizontalPadding),
        itemCount: groups.length,
        itemBuilder: (context, index) {
          final group = groups[index];
          return Padding(
            padding: const EdgeInsets.only(right: _itemSpacing),
            child: _WatchHistoryCard(
              key: ValueKey('history_${group.primaryItem.id}'),
              group: group,
              width: _mobileItemWidth,
              onTap: () => _navigateToDetail(group.primaryItem),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDesktopList(List<WatchHistoryGroup> groups) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth - _horizontalPadding * 2;
        final maxItemCount = ((availableWidth + _itemSpacing) /
                (_desktopMinItemWidth + _itemSpacing))
            .floor();
        final bool shouldShrink = groups.length > maxItemCount && maxItemCount > 0;
        final itemWidth = shouldShrink
            ? (availableWidth - (maxItemCount - 1) * _itemSpacing) / maxItemCount
            : _desktopMinItemWidth;
        final imageHeight = itemWidth * 9 / 16;
        final textScaler = MediaQuery.textScalerOf(context);
        final textAreaHeight = textScaler.scale(40) + 2 + textScaler.scale(16);
        final listHeight = imageHeight + 8 + textAreaHeight;

        return ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: SizedBox(
            height: listHeight,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: _horizontalPadding),
              itemCount: groups.length,
              separatorBuilder: (_, _) => const SizedBox(width: _itemSpacing),
              itemBuilder: (context, index) {
                final group = groups[index];
                return _WatchHistoryCard(
                  key: ValueKey('history_${group.primaryItem.id}'),
                  group: group,
                  width: itemWidth,
                  onTap: () => _navigateToDetail(group.primaryItem),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _navigateToDetail(WatchHistoryItem item) async {
    final title = item.buildTitle();
    if (item.mediaType == 'movie') {
      await context.push(
        '/player/movie/${item.mediaId}',
        extra: {'position': item.position, 'title': title},
      );
    } else if (item.episodeId != null && item.mediaInfo?.episodeInfo != null) {
      final episodeInfo = item.mediaInfo!.episodeInfo!;
      if (!mounted) return;
      // 不等待剧集列表加载，直接跳转播放器
      await context.push(
        '/player/episode/${item.mediaId}/${episodeInfo.seasonId}/${item.episodeId}',
        extra: {'position': item.position, 'title': title},
      );
    } else {
      context.push('/tvshow/${item.mediaId}');
      return;
    }
    if (!mounted) return;
    ref.read(watchHistoryProvider.notifier).refresh();
  }
}

/// 观看历史卡片（带进度条）
class _WatchHistoryCard extends ConsumerStatefulWidget {
  /// 合并后的观看历史分组
  final WatchHistoryGroup group;
  final VoidCallback? onTap;
  final double width;

  const _WatchHistoryCard({
    super.key,
    required this.group,
    this.onTap,
    this.width = 140,
  });

  @override
  ConsumerState<_WatchHistoryCard> createState() => _WatchHistoryCardState();
}

class _WatchHistoryCardState extends ConsumerState<_WatchHistoryCard> {
  bool _isHovered = false;

  // 主展示记录（默认最新观看的一集）
  WatchHistoryItem get _primaryItem => widget.group.primaryItem;

  // 判断是否为剧集
  bool get _isEpisode =>
      _primaryItem.mediaType == 'tv' &&
      _primaryItem.mediaInfo?.episodeInfo != null;

  // 是否需要显示“多集”叠卡与角标
  bool get _showMultiBadge => widget.group.isMultiEpisode;

  // 获取显示图片路径：剧集用剧照，电影用背景图
  String? get _imagePath {
    final mediaInfo = _primaryItem.mediaInfo;
    final episodeInfo = mediaInfo?.episodeInfo;
    if (_isEpisode && episodeInfo?.stillPath != null && episodeInfo!.stillPath!.isNotEmpty) {
      return episodeInfo.stillPath;
    }
    return mediaInfo?.backdropPath ?? mediaInfo?.posterPath;
  }

  // 获取显示标题
  String get _displayTitle {
    final mediaInfo = _primaryItem.mediaInfo;
    if (mediaInfo == null) return '未知';

    final episodeInfo = mediaInfo.episodeInfo;
    if (_isEpisode && episodeInfo != null) {
      // 格式：资源名称 第X季 第X集 集标题
      final parts = <String>[mediaInfo.title];
      if (episodeInfo.seasonNumber > 0) {
        parts.add('第${episodeInfo.seasonNumber}季');
      }
      parts.add('第${episodeInfo.episodeNumber}集');
      if (episodeInfo.episodeName != null && episodeInfo.episodeName!.isNotEmpty) {
        parts.add(episodeInfo.episodeName!);
      }
      return parts.join(' ');
    }
    return mediaInfo.title;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final serverBaseUrl = ref.watch(serverUrlProvider);
    final accessToken = ref.watch(authProvider).tokens?.accessToken;
    // 统一使用 16:9 比例
    final imageHeight = widget.width * 9 / 16;
    // 叠卡偏移量（仅多集时生效）
    final stackOffset = _showMultiBadge ? 6.0 : 0.0;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: widget.width,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              TapFeedback(
                onTap: widget.onTap,
                borderRadius: BorderRadius.circular(8),
                child: AnimatedScale(
                  scale: _isHovered ? 1.05 : 1.0,
                  duration: const Duration(milliseconds: 150),
                  curve: Curves.easeOut,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: widget.width,
                    height: imageHeight,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: _isHovered ? 0.3 : 0.15,
                          ),
                          blurRadius: _isHovered ? 16 : 8,
                          offset: Offset(0, _isHovered ? 8 : 4),
                        ),
                      ],
                    ),
                    // 使用 Stack 叠加“多集”视觉效果
                    child: Stack(
                      children: [
                        if (_showMultiBadge) ...[
                          Positioned(
                            left: stackOffset * 2,
                            top: stackOffset * 2,
                            right: 0,
                            bottom: 0,
                            child: _buildStackedCardShadow(theme),
                          ),
                          Positioned(
                            left: stackOffset,
                            top: stackOffset,
                            right: stackOffset,
                            bottom: stackOffset,
                            child: _buildStackedCardShadow(theme),
                          ),
                        ],
                        Positioned(
                          left: 0,
                          top: 0,
                          right: _showMultiBadge ? stackOffset * 2 : 0,
                          bottom: _showMultiBadge ? stackOffset * 2 : 0,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                _buildImage(serverBaseUrl, accessToken),
                                // 进度条
                                Positioned(
                                  left: 0,
                                  right: 0,
                                  bottom: 0,
                                  child: Container(
                                    height: 4,
                                    color: Colors.black45,
                                    child: FractionallySizedBox(
                                      alignment: Alignment.centerLeft,
                                      widthFactor: _primaryItem.progress.clamp(0.0, 1.0),
                                      child: Container(
                                        color: const Color(0xFF3D5BF6),
                                      ),
                                    ),
                                  ),
                                ),
                                if (_showMultiBadge)
                                  Positioned(
                                    top: 6,
                                    right: 6,
                                    child: _buildCountBadge(theme),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _displayTitle,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                _getSubtitle(),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getSubtitle() {
    final progress = (_primaryItem.progress * 100).toInt();
    return '已观看 $progress%';
  }

  Widget _buildImage(String? serverBaseUrl, String? accessToken) {
    final imagePath = _imagePath;
    if (imagePath != null && imagePath.isNotEmpty) {
      final imageUrl = ImageProxy.proxyTMDBIfNeeded(imagePath, serverBaseUrl);
      return CachedNetworkImage(
        imageUrl: imageUrl,
        httpHeaders:
            accessToken != null
                ? {'Authorization': 'Bearer $accessToken'}
                : null,
        fit: BoxFit.cover,
        placeholder: (context, url) => _buildPlaceholder(),
        errorWidget: (context, url, error) => _buildPlaceholder(),
      );
    }
    return _buildPlaceholder();
  }

  Widget _buildPlaceholder() {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(Icons.movie_outlined, size: 40, color: theme.colorScheme.outline),
      ),
    );
  }

  /// 叠卡背景：用浅色卡片模拟"多张卡片"的层次感
  Widget _buildStackedCardShadow(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
    );
  }

  /// 多集数量角标
  Widget _buildCountBadge(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        '${widget.group.count}集',
        style: theme.textTheme.labelSmall?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
