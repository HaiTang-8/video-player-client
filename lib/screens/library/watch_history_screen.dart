import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/utils/image_proxy.dart';
import '../../core/widgets/desktop_app_bar.dart';
import '../../core/widgets/dialog_utils.dart';
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
      if (!mounted) return;
      ref.read(watchHistoryProvider.notifier).load(limit: 100);
    });
  }

  void _toggleEditMode() {
    setState(() {
      _isEditMode = !_isEditMode;
      if (!_isEditMode) _selectedIds.clear();
    });
  }

  /// 切换合并/不合并展示模式
  Future<void> _toggleMergeMode() async {
    await ref.read(watchHistoryMergeEnabledProvider.notifier).toggle();
    if (!mounted) return;
    setState(() {
      _isEditMode = false;
      _selectedIds.clear();
    });
  }

  /// 切换某个“合并卡片”的选中状态（实际操作所有包含的记录 ID）
  void _toggleSelection(WatchHistoryGroup group) {
    final ids = _groupIds(group);
    final isSelected = ids.every(_selectedIds.contains);
    setState(() {
      if (isSelected) {
        _selectedIds.removeAll(ids);
      } else {
        _selectedIds.addAll(ids);
      }
    });
  }

  /// 判断当前分组是否整体选中
  bool _isGroupSelected(WatchHistoryGroup group) {
    final ids = _groupIds(group);
    return ids.isNotEmpty && ids.every(_selectedIds.contains);
  }

  /// 获取分组内全部记录 ID（用于批量删除/选择）
  List<int> _groupIds(WatchHistoryGroup group) {
    return group.items.map((item) => item.id).toList();
  }

  Future<void> _deleteSelected() async {
    if (_selectedIds.isEmpty) return;
    final confirmed = await DialogUtils.showConfirmDialog(
      context: context,
      title: '确认删除',
      content: '确定要删除选中的 ${_selectedIds.length} 条记录吗？',
      confirmText: '删除',
      isDestructive: true,
    );
    if (confirmed != true) return;
    final ids = _selectedIds.toList();
    final success = await ref.read(watchHistoryProvider.notifier).deleteBatch(ids);
    if (!mounted) return;
    if (success) {
      setState(() => _selectedIds.clear());
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('删除失败，请重试')),
      );
    }
  }

  Future<void> _deleteAll() async {
    final confirmed = await DialogUtils.showConfirmDialog(
      context: context,
      title: '确认清空',
      content: '确定要清空所有观看记录吗？',
      confirmText: '确定',
      isDestructive: true,
    );
    if (confirmed != true) return;
    final success = await ref.read(watchHistoryProvider.notifier).deleteAll();
    if (!mounted) return;
    if (success) {
      setState(() {
        _selectedIds.clear();
        _isEditMode = false;
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('清空失败，请重试')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(watchHistoryProvider);
    final isDesktop = WindowControls.isDesktop;
    final mergeEnabled = ref.watch(watchHistoryMergeEnabledProvider);
    // 合并后的观看历史列表（同一剧集多集合并展示）
    final groups = state.groupedItems(mergeEpisodes: mergeEnabled);
    final hasItems = groups.isNotEmpty;

    final editAction = (!mergeEnabled && hasItems)
        ? CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            onPressed: _toggleEditMode,
            child: Text(_isEditMode ? '完成' : '编辑'),
          )
        : null;

    final toggleAction = CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      onPressed: _toggleMergeMode,
      child: Text(mergeEnabled ? '列表' : '合并'),
    );

    final actions = <Widget>[
      toggleAction,
      if (editAction != null) editAction,
    ];

    return Scaffold(
      appBar: isDesktop
          ? DesktopAppBar(
              title: const Text('最近观看'),
              onBack: () => context.pop(),
              actions: actions,
            )
          : MobileAppBar(
              title: const Text('最近观看'),
              onBack: () => context.pop(),
              actions: actions,
            ),
      body: Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => ref.read(watchHistoryProvider.notifier).load(limit: 100),
              child: _buildBody(state, groups),
            ),
          ),
          if (!mergeEnabled && _isEditMode && hasItems) _buildBottomBar(),
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

  Widget _buildBody(WatchHistoryState state, List<WatchHistoryGroup> groups) {
    if (state.isLoading && state.items.isEmpty) {
      return const GridSkeletonLoader();
    }

    if (state.error != null && state.items.isEmpty) {
      return AppErrorWidget(
        message: state.error!,
        onRetry: () => ref.read(watchHistoryProvider.notifier).load(limit: 100),
        scrollable: true,
      );
    }

    if (groups.isEmpty) {
      return const EmptyWidget(
        message: '暂无观看记录',
        icon: Icons.history,
        scrollable: true,
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
      itemCount: groups.length,
      itemBuilder: (context, index) {
        final group = groups[index];
        return _WatchHistoryGridItem(
          group: group,
          isEditMode: _isEditMode,
          isSelected: _isGroupSelected(group),
          onTap: _isEditMode
              ? () => _toggleSelection(group)
              : () => _navigateToDetail(group.primaryItem),
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
}

class _WatchHistoryGridItem extends ConsumerWidget {
  /// 合并后的观看历史分组
  final WatchHistoryGroup group;
  final VoidCallback? onTap;
  final bool isEditMode;
  final bool isSelected;

  const _WatchHistoryGridItem({
    required this.group,
    this.onTap,
    this.isEditMode = false,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final serverBaseUrl = ref.watch(serverUrlProvider);
    // 主展示记录（默认最新观看的一集）
    final primaryItem = group.primaryItem;
    // 是否显示多集叠卡与角标
    final showMultiBadge = group.isMultiEpisode;
    // 叠卡偏移量（仅多集时生效）
    final stackOffset = showMultiBadge ? 6.0 : 0.0;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  children: [
                    if (showMultiBadge) ...[
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
                      right: showMultiBadge ? stackOffset * 2 : 0,
                      bottom: showMultiBadge ? stackOffset * 2 : 0,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            _buildImage(context, serverBaseUrl, primaryItem),
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: Container(
                                height: 4,
                                color: Colors.black45,
                                child: FractionallySizedBox(
                                  alignment: Alignment.centerLeft,
                                  widthFactor: primaryItem.progress.clamp(0.0, 1.0),
                                  child: Container(color: const Color(0xFF3D5BF6)),
                                ),
                              ),
                            ),
                            if (showMultiBadge)
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
              const SizedBox(height: 8),
              Text(
                _displayTitle(primaryItem),
                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                '已观看 ${(primaryItem.progress * 100).toInt()}%',
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

  /// 构建标题（主展示记录）
  String _displayTitle(WatchHistoryItem item) {
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

  /// 获取主展示记录的图片路径
  String? _imagePath(WatchHistoryItem item) {
    final mediaInfo = item.mediaInfo;
    final episodeInfo = mediaInfo?.episodeInfo;
    if (item.mediaType == 'tv' && episodeInfo?.stillPath != null && episodeInfo!.stillPath!.isNotEmpty) {
      return episodeInfo.stillPath;
    }
    return mediaInfo?.backdropPath ?? mediaInfo?.posterPath;
  }

  Widget _buildImage(BuildContext context, String? serverBaseUrl, WatchHistoryItem item) {
    final imagePath = _imagePath(item);
    if (imagePath != null && imagePath.isNotEmpty) {
      final imageUrl = ImageProxy.proxyTMDBIfNeeded(imagePath, serverBaseUrl);
      return CachedNetworkImage(
        imageUrl: imageUrl,
        fit: BoxFit.cover,
        placeholder: (ctx, url) => _buildPlaceholder(context),
        errorWidget: (ctx, url, error) => _buildPlaceholder(context),
      );
    }
    return _buildPlaceholder(context);
  }

  Widget _buildPlaceholder(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Center(child: Icon(Icons.movie_outlined, size: 40, color: theme.colorScheme.outline)),
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
        '${group.count}集',
        style: theme.textTheme.labelSmall?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
