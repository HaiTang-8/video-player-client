import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/utils/image_proxy.dart';
import '../../core/widgets/desktop_app_bar.dart';
import '../../core/widgets/skeleton_loader.dart';
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
      return const GridSkeletonLoader();
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

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 280,
        childAspectRatio: 1.35,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: state.items.length,
      itemBuilder: (context, index) {
        final item = state.items[index];
        return _WatchHistoryGridItem(
          item: item,
          isEditMode: _isEditMode,
          isSelected: _selectedIds.contains(item.id),
          onTap: _isEditMode ? () => _toggleSelection(item.id) : () => _navigateToDetail(item),
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

class _WatchHistoryGridItem extends ConsumerWidget {
  final WatchHistoryItem item;
  final VoidCallback? onTap;
  final bool isEditMode;
  final bool isSelected;

  const _WatchHistoryGridItem({
    required this.item,
    this.onTap,
    this.isEditMode = false,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final serverBaseUrl = ref.watch(serverUrlProvider);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _buildImage(serverBaseUrl),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Container(
                          height: 4,
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
              const SizedBox(height: 8),
              Text(
                _displayTitle,
                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                '已观看 ${(item.progress * 100).toInt()}%',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                maxLines: 1,
              ),
            ],
          ),
          if (isEditMode)
            Positioned(
              top: 8,
              right: 8,
              child: Icon(
                isSelected ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.circle,
                color: isSelected ? CupertinoColors.activeBlue : CupertinoColors.white,
                size: 24,
              ),
            ),
        ],
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
      return parts.join(' ');
    }
    return mediaInfo.title;
  }

  String? get _imagePath {
    final mediaInfo = item.mediaInfo;
    final episodeInfo = mediaInfo?.episodeInfo;
    if (item.mediaType == 'tv' && episodeInfo?.stillPath != null && episodeInfo!.stillPath!.isNotEmpty) {
      return episodeInfo.stillPath;
    }
    return mediaInfo?.backdropPath ?? mediaInfo?.posterPath;
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
      child: const Center(child: Icon(Icons.movie_outlined, size: 40, color: Colors.grey)),
    );
  }
}
