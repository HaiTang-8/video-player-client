import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/utils/image_proxy.dart';
import '../../core/widgets/desktop_app_bar.dart';
import '../../core/widgets/loading_widget.dart';
import '../../core/widgets/mobile_app_bar.dart';
import '../../core/window/window_controls.dart';
import '../../data/models/models.dart';
import '../../providers/providers.dart';

class WatchHistoryScreen extends ConsumerStatefulWidget {
  const WatchHistoryScreen({super.key});

  @override
  ConsumerState<WatchHistoryScreen> createState() => _WatchHistoryScreenState();
}

class _WatchHistoryScreenState extends ConsumerState<WatchHistoryScreen> {
  bool _isEditMode = false;
  final Set<int> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(watchHistoryProvider.notifier).load(limit: 100);
    });
  }

  void _toggleEditMode() {
    setState(() {
      _isEditMode = !_isEditMode;
      if (!_isEditMode) _selectedIds.clear();
    });
  }

  void _toggleSelection(int id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  Future<void> _deleteSelected() async {
    if (_selectedIds.isEmpty) return;
    final ids = _selectedIds.toList();
    await ref.read(watchHistoryProvider.notifier).deleteBatch(ids);
    setState(() => _selectedIds.clear());
  }

  Future<void> _deleteAll() async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('确认清空'),
        content: const Text('确定要清空所有观看记录吗？'),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(watchHistoryProvider.notifier).deleteAll();
      setState(() {
        _selectedIds.clear();
        _isEditMode = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(watchHistoryProvider);
    final isDesktop = WindowControls.isDesktop;
    final hasItems = state.items.isNotEmpty;

    final editAction = hasItems
        ? CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            onPressed: _toggleEditMode,
            child: Text(_isEditMode ? '完成' : '编辑'),
          )
        : null;

    return Scaffold(
      appBar: isDesktop
          ? DesktopAppBar(
              title: const Text('最近观看'),
              onBack: () => context.pop(),
              actions: editAction != null ? [editAction] : [],
            )
          : MobileAppBar(
              title: const Text('最近观看'),
              onBack: () => context.pop(),
              actions: editAction != null ? [editAction] : null,
            ),
      body: Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => ref.read(watchHistoryProvider.notifier).load(limit: 100),
              child: _buildBody(state),
            ),
          ),
          if (_isEditMode && hasItems) _buildBottomBar(),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    final hasSelection = _selectedIds.isNotEmpty;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: CupertinoTheme.of(context).barBackgroundColor,
        border: const Border(top: BorderSide(color: CupertinoColors.separator, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: _deleteAll,
              child: const Text('全部清空', style: TextStyle(fontSize: 16)),
            ),
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: hasSelection ? _deleteSelected : null,
              child: Text(
                '删除',
                style: TextStyle(
                  color: hasSelection ? CupertinoColors.destructiveRed : CupertinoColors.inactiveGray,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
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
        if (_isEditMode) {
          return _WatchHistoryListItem(
            item: item,
            isEditMode: true,
            isSelected: _selectedIds.contains(item.id),
            onTap: () => _toggleSelection(item.id),
          );
        }
        return Dismissible(
          key: ValueKey(item.id),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            color: CupertinoColors.destructiveRed,
            child: const Icon(CupertinoIcons.delete, color: CupertinoColors.white),
          ),
          onDismissed: (_) => ref.read(watchHistoryProvider.notifier).delete(item.id),
          child: _WatchHistoryListItem(
            item: item,
            onTap: () => _navigateToDetail(item),
          ),
        );
      },
    );
  }

  Future<void> _navigateToDetail(WatchHistoryItem item) async {
    if (item.completed) {
      if (item.mediaType == 'movie') {
        context.push('/movie/${item.mediaId}');
      } else {
        context.push('/tvshow/${item.mediaId}');
      }
    } else {
      final title = _buildTitle(item);
      if (item.mediaType == 'movie') {
        await context.push(
          '/player/movie/${item.mediaId}',
          extra: {'position': item.position, 'title': title},
        );
      } else if (item.episodeId != null && item.mediaInfo?.episodeInfo != null) {
        final episodeInfo = item.mediaInfo!.episodeInfo!;
        if (!mounted) return;
        final episodes = await ref.read(
          seasonEpisodesProvider((tvShowId: item.mediaId, seasonId: episodeInfo.seasonId)).future,
        );
        if (!mounted) return;
        await context.push(
          '/player/episode/${item.mediaId}/${episodeInfo.seasonId}/${item.episodeId}',
          extra: {'position': item.position, 'title': title, 'episodes': episodes},
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
  final bool isEditMode;
  final bool isSelected;

  const _WatchHistoryListItem({
    required this.item,
    this.onTap,
    this.isEditMode = false,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final serverBaseUrl = ref.watch(serverUrlProvider);
    final isEpisode = item.mediaType == 'tv' && item.mediaInfo?.episodeInfo != null;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            if (isEditMode) ...[
              Icon(
                isSelected ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.circle,
                color: isSelected ? CupertinoColors.activeBlue : CupertinoColors.inactiveGray,
                size: 24,
              ),
              const SizedBox(width: 12),
            ],
            ClipRRect(
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
                          color: CupertinoColors.black.withValues(alpha: 0.45),
                          child: FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: item.progress.clamp(0.0, 1.0),
                            child: Container(color: CupertinoColors.activeBlue),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _displayTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(color: CupertinoColors.secondaryLabel),
                  ),
                ],
              ),
            ),
            if (!isEditMode && item.completed)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: CupertinoColors.activeGreen,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  '已看完',
                  style: TextStyle(color: CupertinoColors.white, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
          ],
        ),
      ),
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
      color: CupertinoColors.systemGrey5,
      child: const Center(child: Icon(CupertinoIcons.film, size: 24, color: CupertinoColors.systemGrey)),
    );
  }
}
