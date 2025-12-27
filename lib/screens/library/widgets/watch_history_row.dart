import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
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
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 220, // 适应 16:9 剧照(124) + 标题(~80) + 间距
          child: state.isLoading && state.items.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : state.error != null && state.items.isEmpty
                  ? Center(
                      child: Text(
                        '加载失败',
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    )
                  : ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: state.items.length,
                      itemBuilder: (context, index) {
                        final item = state.items[index];
                        return Padding(
                          padding: const EdgeInsets.only(right: 16),
                          child: _WatchHistoryCard(
                            item: item,
                            width: 220,
                            onTap: () => _navigateToDetail(item),
                          ),
                        );
                      },
                    ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  void _navigateToDetail(WatchHistoryItem item) {
    if (item.mediaType == 'movie') {
      context.push('/movie/${item.mediaId}');
    } else {
      context.push('/tvshow/${item.mediaId}');
    }
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

  // 获取显示图片路径：剧集用剧照，电影用海报
  String? get _imagePath {
    final episodeInfo = widget.item.mediaInfo?.episodeInfo;
    if (_isEpisode && episodeInfo?.stillPath != null && episodeInfo!.stillPath!.isNotEmpty) {
      return episodeInfo.stillPath;
    }
    return widget.item.mediaInfo?.posterPath;
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
    // 剧集使用 16:9 比例，电影使用 2:3 比例
    final imageHeight = _isEpisode ? widget.width * 9 / 16 : widget.width * 1.5;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
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
                AnimatedContainer(
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
                        if (!widget.item.completed)
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
                        // 已看完标记
                        if (widget.item.completed)
                          Positioned(
                            bottom: 8,
                            right: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.green.shade600,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                '已看完',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _displayTitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
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
    if (widget.item.completed) {
      return _formatWatchedAt(widget.item.watchedAt);
    }
    final progress = (widget.item.progress * 100).toInt();
    return '已观看 $progress%';
  }

  String _formatWatchedAt(DateTime watchedAt) {
    final now = DateTime.now();
    final diff = now.difference(watchedAt);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes}分钟前';
    if (diff.inDays < 1) return '${diff.inHours}小时前';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    return '${watchedAt.month}月${watchedAt.day}日';
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
