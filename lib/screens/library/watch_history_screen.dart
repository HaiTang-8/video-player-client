import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/utils/image_proxy.dart';
import '../../core/widgets/app_back_button.dart';
import '../../core/widgets/desktop_title_bar.dart';
import '../../core/widgets/loading_widget.dart';
import '../../core/window/window_controls.dart';
import '../../data/models/models.dart';
import '../../providers/providers.dart';

class WatchHistoryScreen extends ConsumerStatefulWidget {
  const WatchHistoryScreen({super.key});

  @override
  ConsumerState<WatchHistoryScreen> createState() => _WatchHistoryScreenState();
}

class _WatchHistoryScreenState extends ConsumerState<WatchHistoryScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(watchHistoryProvider.notifier).load(limit: 100);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(watchHistoryProvider);
    final isDesktop = WindowControls.isDesktop;

    return Scaffold(
      appBar: isDesktop
          ? DesktopTitleBar(
              leading: AppBackButton(onPressed: () => context.pop()),
              title: const Text('最近观看'),
              centerTitle: true,
            )
          : AppBar(
              leadingWidth: kAppBackButtonWidth,
              leading: AppBackButton(onPressed: () => context.pop()),
              title: const Text('最近观看'),
            ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(watchHistoryProvider.notifier).load(limit: 100),
        child: _buildBody(state),
      ),
    );
  }

  Widget _buildBody(WatchHistoryState state) {
    if (state.isLoading && state.items.isEmpty) {
      return const LoadingWidget(message: '加载中...');
    }

    if (state.error != null && state.items.isEmpty) {
      return AppErrorWidget(
        message: state.error!,
        onRetry: () => ref.read(watchHistoryProvider.notifier).load(limit: 100),
      );
    }

    if (state.items.isEmpty) {
      return const EmptyWidget(
        message: '暂无观看记录',
        icon: Icons.history,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: state.items.length,
      itemBuilder: (context, index) {
        final item = state.items[index];
        return _WatchHistoryListItem(
          item: item,
          onTap: () => _navigateToDetail(item),
        );
      },
    );
  }

  void _navigateToDetail(WatchHistoryItem item) {
    if (item.completed) {
      if (item.mediaType == 'movie') {
        context.push('/movie/${item.mediaId}');
      } else {
        context.push('/tvshow/${item.mediaId}');
      }
    } else {
      final title = _buildTitle(item);
      if (item.mediaType == 'movie') {
        context.push(
          '/player/movie/${item.mediaId}',
          extra: {'position': item.position, 'title': title},
        );
      } else if (item.episodeId != null && item.mediaInfo?.episodeInfo != null) {
        final episodeInfo = item.mediaInfo!.episodeInfo!;
        context.push(
          '/player/episode/${item.mediaId}/${episodeInfo.seasonId}/${item.episodeId}',
          extra: {'position': item.position, 'title': title},
        );
      } else {
        context.push('/tvshow/${item.mediaId}');
      }
    }
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

class _WatchHistoryListItem extends ConsumerWidget {
  final WatchHistoryItem item;
  final VoidCallback? onTap;

  const _WatchHistoryListItem({required this.item, this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final serverBaseUrl = ref.watch(serverUrlProvider);
    final isEpisode = item.mediaType == 'tv' && item.mediaInfo?.episodeInfo != null;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: isEpisode ? 100 : 60,
          height: isEpisode ? 56 : 90,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _buildImage(serverBaseUrl, isEpisode),
              if (!item.completed)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    height: 3,
                    color: Colors.black45,
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: item.progress.clamp(0.0, 1.0),
                      child: Container(color: const Color(0xFF3D5BF6)),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      title: Text(
        _displayTitle,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        _subtitle,
        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
      ),
      trailing: item.completed
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.green.shade600,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                '已看完',
                style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
              ),
            )
          : null,
      onTap: onTap,
    );
  }

  String get _displayTitle {
    final mediaInfo = item.mediaInfo;
    if (mediaInfo == null) return '未知';
    final episodeInfo = mediaInfo.episodeInfo;
    if (item.mediaType == 'tv' && episodeInfo != null) {
      final parts = <String>[mediaInfo.title];
      if (episodeInfo.seasonNumber > 0) parts.add('第${episodeInfo.seasonNumber}季');
      parts.add('第${episodeInfo.episodeNumber}集');
      if (episodeInfo.episodeName != null && episodeInfo.episodeName!.isNotEmpty) {
        parts.add(episodeInfo.episodeName!);
      }
      return parts.join(' ');
    }
    return mediaInfo.title;
  }

  String get _subtitle {
    if (item.completed) return _formatWatchedAt(item.watchedAt);
    return '已观看 ${(item.progress * 100).toInt()}%';
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

  String? get _imagePath {
    final episodeInfo = item.mediaInfo?.episodeInfo;
    if (item.mediaType == 'tv' && episodeInfo?.stillPath != null && episodeInfo!.stillPath!.isNotEmpty) {
      return episodeInfo.stillPath;
    }
    return item.mediaInfo?.posterPath;
  }

  Widget _buildImage(String? serverBaseUrl, bool isEpisode) {
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
      child: const Center(child: Icon(Icons.movie_outlined, size: 24, color: Colors.grey)),
    );
  }
}
