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
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(watchHistoryProvider.notifier).load(limit: 20);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(watchHistoryProvider);

    // 无数据时不显示
    if (!state.isLoading && state.items.isEmpty) {
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
                Icon(
                  Icons.history,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  '最近观看',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${state.items.length}',
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
        _buildContent(theme, state),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildContent(ThemeData theme, WatchHistoryState state) {
    if (state.isLoading && state.items.isEmpty) {
      return const SizedBox(
        height: 190,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (state.error != null && state.items.isEmpty) {
      return SizedBox(
        height: 190,
        child: Center(
          child: Text('加载失败', style: TextStyle(color: theme.colorScheme.error)),
        ),
      );
    }

    if (!WindowControls.isDesktop) {
      return _buildMobileList(state.items);
    }
    return _buildDesktopList(state.items);
  }

  Widget _buildMobileList(List<WatchHistoryItem> items) {
    return SizedBox(
      height: 190,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: _horizontalPadding),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          return Padding(
            padding: const EdgeInsets.only(right: _itemSpacing),
            child: _WatchHistoryCard(
              item: item,
              width: _mobileItemWidth,
              onTap: () => _navigateToDetail(item),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDesktopList(List<WatchHistoryItem> items) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth - _horizontalPadding * 2;
        final itemCount = ((availableWidth + _itemSpacing) /
                (_desktopMinItemWidth + _itemSpacing))
            .floor();
        final itemWidth = itemCount > 0
            ? (availableWidth - (itemCount - 1) * _itemSpacing) / itemCount
            : _desktopMinItemWidth;
        // 图片高度 + 间距 + 文字区域
        final imageHeight = itemWidth * 9 / 16;
        final listHeight = imageHeight + 8 + 40 + 2 + 16;

        return SizedBox(
          height: listHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: _horizontalPadding),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: _itemSpacing),
            itemBuilder: (context, index) {
              final item = items[index];
              return _WatchHistoryCard(
                item: item,
                width: itemWidth,
                onTap: () => _navigateToDetail(item),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _navigateToDetail(WatchHistoryItem item) async {
    final title = _buildTitle(item);
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
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    ref.read(watchHistoryProvider.notifier).refresh();
  }

  String _buildTitle(WatchHistoryItem item) {
    final mediaInfo = item.mediaInfo;
    if (mediaInfo == null) return '';

    final episodeInfo = mediaInfo.episodeInfo;
    if (item.mediaType == 'tv' && episodeInfo != null) {
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
}

/// 观看历史卡片（带进度条）
class _WatchHistoryCard extends ConsumerStatefulWidget {
  final WatchHistoryItem item;
  final VoidCallback? onTap;
  final double width;

  const _WatchHistoryCard({
    required this.item,
    this.onTap,
    this.width = 140,
  });

  @override
  ConsumerState<_WatchHistoryCard> createState() => _WatchHistoryCardState();
}

class _WatchHistoryCardState extends ConsumerState<_WatchHistoryCard> {
  bool _isHovered = false;

  // 判断是否为剧集
  bool get _isEpisode =>
      widget.item.mediaType == 'tv' &&
      widget.item.mediaInfo?.episodeInfo != null;

  // 获取显示图片路径：剧集用剧照，电影用背景图
  String? get _imagePath {
    final mediaInfo = widget.item.mediaInfo;
    final episodeInfo = mediaInfo?.episodeInfo;
    if (_isEpisode && episodeInfo?.stillPath != null && episodeInfo!.stillPath!.isNotEmpty) {
      return episodeInfo.stillPath;
    }
    return mediaInfo?.backdropPath ?? mediaInfo?.posterPath;
  }

  // 获取显示标题
  String get _displayTitle {
    final mediaInfo = widget.item.mediaInfo;
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
    // 统一使用 16:9 比例
    final imageHeight = widget.width * 9 / 16;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedScale(
          scale: _isHovered ? 1.05 : 1.0,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          child: SizedBox(
            width: widget.width,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                TapFeedback(
                  onTap: widget.onTap,
                  borderRadius: BorderRadius.circular(8),
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
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _buildImage(serverBaseUrl),
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
                              widthFactor: widget.item.progress.clamp(0.0, 1.0),
                              child: Container(
                                color: const Color(0xFF3D5BF6),
                              ),
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
      ),
    );
  }

  String _getSubtitle() {
    final progress = (widget.item.progress * 100).toInt();
    return '已观看 $progress%';
  }

  Widget _buildImage(String? serverBaseUrl) {
    final imagePath = _imagePath;
    if (imagePath != null && imagePath.isNotEmpty) {
      final imageUrl = ImageProxy.proxyTMDBIfNeeded(imagePath, serverBaseUrl);
      return CachedNetworkImage(
        imageUrl: imageUrl,
        fit: BoxFit.cover,
        placeholder: (context, url) => _buildPlaceholder(),
        errorWidget: (context, url, error) => _buildPlaceholder(),
      );
    }
    return _buildPlaceholder();
  }

  Widget _buildPlaceholder() {
    return Container(
      color: Colors.grey[300],
      child: const Center(
        child: Icon(Icons.movie_outlined, size: 40, color: Colors.grey),
      ),
    );
  }
}
