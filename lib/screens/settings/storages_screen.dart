import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;
import '../../core/theme/app_colors.dart';
import '../../core/utils/responsive.dart';
import '../../core/widgets/desktop_app_bar.dart';
import '../../core/widgets/dialog_utils.dart';
import '../../core/widgets/mobile_app_bar.dart';
import '../../core/window/window_controls.dart';
import '../../core/widgets/skeleton_loader.dart';
import '../../data/models/models.dart';
import '../../providers/providers.dart';
import 'storage_type.dart';

/// 存储源管理页面
class StoragesScreen extends ConsumerStatefulWidget {
  const StoragesScreen({super.key});

  @override
  ConsumerState<StoragesScreen> createState() => _StoragesScreenState();
}

class _StoragesScreenState extends ConsumerState<StoragesScreen> {
  // 防止“导出/导入”在短时间内被触发多次（例如 dropdown 关闭动画期间重复触发），
  // 否则会出现：首次点击弹窗闪一下无响应、第二次点击叠两个弹窗、点击确定像“没反应”等问题。
  bool _exporting = false;
  bool _importing = false;
  StorageType? _typeFilter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(storagesProvider.notifier).loadStorages();
    });
  }

  @override
  Widget build(BuildContext context) {
    final storagesAsync = ref.watch(storagesProvider);
    final isDesktop = WindowControls.isDesktop;
    final compact = context.windowSizeClass.isCompact;

    final actions = [
      if (compact)
        shadcn.IconButton.ghost(
          icon: const Icon(CupertinoIcons.add),
          onPressed: () => _openAddStorage(context),
        ),
      Builder(
        builder:
            (buttonContext) => shadcn.IconButton.ghost(
              icon: const Icon(CupertinoIcons.ellipsis_vertical),
              onPressed: () {
                shadcn.showDropdown(
                  context: buttonContext,
                  builder:
                      (context) => shadcn.DropdownMenu(
                        children: [
                          shadcn.MenuButton(
                            leading: const Icon(
                              CupertinoIcons.square_arrow_up,
                              size: 18,
                            ),
                            child: const Text('导出'),
                            onPressed: (menuContext) {
                              shadcn.closeOverlay(menuContext);
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (!mounted) return;
                                unawaited(_exportStorages());
                              });
                            },
                          ),
                          shadcn.MenuButton(
                            leading: const Icon(
                              CupertinoIcons.square_arrow_down,
                              size: 18,
                            ),
                            child: const Text('导入'),
                            onPressed: (menuContext) {
                              shadcn.closeOverlay(menuContext);
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (!mounted) return;
                                unawaited(_importStorages());
                              });
                            },
                          ),
                        ],
                      ),
                );
              },
            ),
      ),
    ];

    return Scaffold(
      appBar:
          isDesktop
              ? DesktopAppBar(
                title: const Text('存储源管理'),
                onBack: () => context.pop(),
                actions: actions,
              )
              : MobileAppBar(
                title: const Text('存储源管理'),
                onBack: () => context.pop(),
                actions: actions,
              ),
      body: storagesAsync.when(
        loading: () => const ListSkeletonLoader(),
        error:
            (error, stack) => AppErrorWidget(
              message: error.toString(),
              onRetry: () => ref.read(storagesProvider.notifier).loadStorages(),
            ),
        data: (storages) => _buildStorageList(context, storages, compact),
      ),
    );
  }

  Future<void> _exportStorages() async {
    if (_exporting) return;
    _exporting = true;
    try {
      await context.push('/storage-manage/export');
    } finally {
      _exporting = false;
    }
  }

  Future<void> _importStorages() async {
    if (_importing) return;
    _importing = true;
    try {
      await context.push<bool>('/storage-manage/import');
    } finally {
      _importing = false;
    }
  }

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.appColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                CupertinoIcons.folder_badge_plus,
                size: 32,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '还没有存储源',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '添加 WebDAV、OpenList 或本地目录，扫描后即可在媒体库中浏览',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: 24),
            shadcn.PrimaryButton(
              onPressed: () => _openAddStorage(context),
              leading: const Icon(CupertinoIcons.add, size: 16),
              child: const Text('添加存储源'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStorageList(
    BuildContext context,
    List<Storage> storages,
    bool compact,
  ) {
    final bottomInset = MediaQuery.paddingOf(context).bottom + 24;
    final groups = StorageType.group(storages);
    final filter =
        !compact && groups.containsKey(_typeFilter) ? _typeFilter : null;
    final visibleGroups =
        filter == null ? groups : {filter: groups[filter]!};

    return RefreshIndicator(
      onRefresh: () => ref.read(storagesProvider.notifier).loadStorages(),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final horizontal =
              compact
                  ? 16.0
                  : ((constraints.maxWidth - _maxContentWidth) / 2).clamp(
                    24.0,
                    double.infinity,
                  );

          return CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              if (storages.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _buildEmptyState(context),
                )
              else ...[
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    horizontal,
                    compact ? 12 : 24,
                    horizontal,
                    compact ? 4 : 8,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: _buildHeader(
                      context,
                      storages,
                      groups,
                      filter,
                      compact,
                    ),
                  ),
                ),
                for (final entry in visibleGroups.entries) ...[
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      horizontal + 4,
                      compact ? 16 : 20,
                      horizontal,
                      compact ? 8 : 12,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: _TypeSectionHeader(
                        type: entry.key,
                        count: entry.value.length,
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: EdgeInsets.symmetric(horizontal: horizontal),
                    sliver:
                        compact
                            ? SliverToBoxAdapter(
                              child: _buildGroupedList(context, entry.value),
                            )
                            : _buildGrid(context, entry.value),
                  ),
                ],
                SliverToBoxAdapter(child: SizedBox(height: bottomInset)),
              ],
            ],
          );
        },
      ),
    );
  }

  static const double _maxContentWidth = 1120;

  Widget _buildHeader(
    BuildContext context,
    List<Storage> storages,
    Map<StorageType, List<Storage>> groups,
    StorageType? filter,
    bool compact,
  ) {
    final theme = Theme.of(context);
    final colors = context.appColors;
    final enabledCount = storages.where((s) => s.enabled).length;
    final summary = '${storages.length} 个存储源 · $enabledCount 个已启用';

    if (compact) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          summary,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.textSecondary,
          ),
        ),
      );
    }

    final titleRow = Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '全部存储源',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                summary,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        shadcn.PrimaryButton(
          onPressed: () => _openAddStorage(context),
          leading: const Icon(CupertinoIcons.add, size: 16),
          child: const Text('添加存储源'),
        ),
      ],
    );

    if (groups.length < 2) return titleRow;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        titleRow,
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _TypeFilterButton(
              label: '全部 ${storages.length}',
              selected: filter == null,
              onPressed: () => setState(() => _typeFilter = null),
            ),
            for (final entry in groups.entries)
              _TypeFilterButton(
                icon: entry.key.icon,
                label: '${entry.key.label} ${entry.value.length}',
                selected: filter == entry.key,
                onPressed: () => setState(() => _typeFilter = entry.key),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildGroupedList(BuildContext context, List<Storage> storages) {
    final colors = context.appColors;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          for (var i = 0; i < storages.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.only(left: 68),
                child: Divider(height: 1, thickness: 0.5, color: colors.divider),
              ),
            _StorageListTile(
              storage: storages[i],
              onBrowse: () => _browseStorage(context, storages[i]),
              onEdit: () => _openEditStorage(context, storages[i]),
              onDelete: () => _deleteStorage(storages[i]),
              onToggleEnabled:
                  (enabled) => _toggleStorageEnabled(storages[i], enabled),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGrid(BuildContext context, List<Storage> storages) {
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
    return SliverGrid(
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 420,
        mainAxisExtent: 172 * textScale,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      delegate: SliverChildBuilderDelegate((context, index) {
        final storage = storages[index];
        return _StorageCard(
          storage: storage,
          onBrowse: () => _browseStorage(context, storage),
          onEdit: () => _openEditStorage(context, storage),
          onDelete: () => _deleteStorage(storage),
          onToggleEnabled: (enabled) => _toggleStorageEnabled(storage, enabled),
        );
      }, childCount: storages.length),
    );
  }

  void _browseStorage(BuildContext context, Storage storage) {
    context.push('/storages/${storage.id}', extra: storage);
  }

  Future<void> _deleteStorage(Storage storage) async {
    final confirmed = await DialogUtils.showConfirmDialog(
      context: context,
      title: '删除存储源',
      content: '确定要删除 "${storage.name}" 吗？',
      confirmText: '删除',
      isDestructive: true,
    );

    if (confirmed == true) {
      final success = await ref
          .read(storagesProvider.notifier)
          .deleteStorage(storage.id);
      if (!success && mounted) {
        DialogUtils.showToast(context: context, message: '删除失败', isError: true);
      }
    }
  }

  Future<void> _toggleStorageEnabled(Storage storage, bool enabled) async {
    if (enabled) {
      final success = await ref
          .read(storagesProvider.notifier)
          .enableStorage(storage.id);
      if (mounted) {
        DialogUtils.showToast(
          context: context,
          message: success ? '存储源已启用' : '启用失败',
          isError: !success,
        );
      }
    } else {
      final result = await _showDisableOptionsDialog(storage);
      if (result == null) return;
      final success = await ref
          .read(storagesProvider.notifier)
          .disableStorage(storage.id, hideMedia: result);
      if (mounted) {
        DialogUtils.showToast(
          context: context,
          message: success ? '存储源已禁用' : '禁用失败',
          isError: !success,
        );
      }
    }
  }

  Future<bool?> _showDisableOptionsDialog(Storage storage) async {
    return DialogUtils.showCustomDialog<bool>(
      context: context,
      builder:
          (context) => shadcn.AlertDialog(
            barrierColor: Colors.transparent,
            surfaceOpacity: 1,
            title: const Text('禁用存储源'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('确定要禁用「${storage.name}」吗？'),
                const SizedBox(height: 12),
                Text(
                  '禁用后，该存储源将不再被扫描。',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            actions: [
              shadcn.OutlineButton(
                onPressed: () => Navigator.pop(context, null),
                child: const Text('取消'),
              ),
              shadcn.OutlineButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('禁用'),
              ),
              shadcn.PrimaryButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('禁用并隐藏'),
              ),
            ],
          ),
    );
  }

  Future<void> _openAddStorage(BuildContext context) async {
    final saved = await context.push<bool>('/storage-manage/new');
    if (saved == true && mounted) {
      DialogUtils.showToast(context: this.context, message: '添加成功');
    }
  }

  Future<void> _openEditStorage(
    BuildContext context,
    Storage storage,
  ) async {
    final saved = await context.push<bool>(
      '/storage-manage/${storage.id}/edit',
      extra: storage,
    );
    if (saved == true && mounted) {
      DialogUtils.showToast(context: this.context, message: '更新成功');
    }
  }
}

String? _storageAddress(Storage storage) {
  final value = storage.settings?['url'] ?? storage.settings?['path'];
  if (value == null || value.trim().isEmpty) return null;
  return value.trim();
}

String _storageShortAddress(Storage storage) {
  final address = _storageAddress(storage);
  if (address == null) return '未配置地址';
  final host = Uri.tryParse(address)?.host ?? '';
  return host.isNotEmpty ? host : address;
}

String? _streamModeLabel(Storage storage) {
  return switch (storage.settings?['stream_mode']) {
    'proxy' => '代理',
    'redirect' => '直连',
    _ => null,
  };
}

/// 存储源类型分组标题
class _TypeSectionHeader extends StatelessWidget {
  final StorageType type;
  final int count;

  const _TypeSectionHeader({required this.type, required this.count});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Row(
      children: [
        Icon(type.icon, size: 16, color: type.color),
        const SizedBox(width: 6),
        Text(
          type.label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: colors.textSecondary,
          ),
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: colors.cardBackground,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '$count',
            style: TextStyle(fontSize: 11, color: colors.textSecondary),
          ),
        ),
      ],
    );
  }
}

/// 桌面端类型筛选按钮
class _TypeFilterButton extends StatelessWidget {
  final IconData? icon;
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  const _TypeFilterButton({
    this.icon,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final leading = icon == null ? null : Icon(icon, size: 14);
    return selected
        ? shadcn.PrimaryButton(
          size: shadcn.ButtonSize.small,
          onPressed: onPressed,
          leading: leading,
          child: Text(label),
        )
        : shadcn.OutlineButton(
          size: shadcn.ButtonSize.small,
          onPressed: onPressed,
          leading: leading,
          child: Text(label),
        );
  }
}

/// 存储源类型图标
class _StorageTypeIcon extends StatelessWidget {
  final StorageType type;
  final bool enabled;

  const _StorageTypeIcon({required this.type, required this.enabled});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final color = enabled ? type.color : colors.iconSecondary;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color.withValues(alpha: enabled ? 0.14 : 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(type.icon, size: 20, color: color),
    );
  }
}

/// 存储源状态标签
class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          height: 1.3,
          fontWeight: FontWeight.w500,
          color: color,
        ),
      ),
    );
  }
}

List<Widget> _buildStatusBadges(
  BuildContext context,
  Storage storage, {
  required bool showStreamMode,
}) {
  final colors = context.appColors;
  final streamMode = showStreamMode ? _streamModeLabel(storage) : null;
  return [
    if (!storage.enabled)
      _StatusBadge(label: '已停用', color: colors.textSecondary),
    if (!storage.enabled && storage.hideWhenDisabled)
      _StatusBadge(
        label: '媒体已隐藏',
        color: Theme.of(context).colorScheme.error,
      ),
    if (streamMode != null)
      _StatusBadge(label: streamMode, color: colors.textSecondary),
  ];
}

/// 存储源更多操作（底部面板）
class _StorageMoreButton extends StatelessWidget {
  final Storage storage;
  final VoidCallback onBrowse;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _StorageMoreButton({
    required this.storage,
    required this.onBrowse,
    required this.onEdit,
    required this.onDelete,
  });

  Future<void> _showActionSheet(BuildContext context) async {
    final colors = context.appColors;
    final action = await showModalBottomSheet<VoidCallback>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      backgroundColor: colors.cardBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        final destructive = theme.colorScheme.error;
        final type = StorageType.fromString(storage.type);
        final address = _storageAddress(storage);

        Widget actionTile(
          IconData icon,
          String label,
          VoidCallback callback, {
          Color? color,
        }) {
          final foreground = color ?? colors.textPrimary;
          return InkWell(
            onTap: () => Navigator.pop(sheetContext, callback),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                children: [
                  Icon(icon, size: 20, color: color ?? colors.iconSecondary),
                  const SizedBox(width: 14),
                  Text(
                    label,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: foreground,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Row(
                  children: [
                    _StorageTypeIcon(type: type, enabled: storage.enabled),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            storage.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: colors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            address ?? '未配置地址',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, thickness: 0.5, color: colors.divider),
              actionTile(CupertinoIcons.folder, '浏览', onBrowse),
              actionTile(CupertinoIcons.pencil, '编辑', onEdit),
              Divider(
                height: 1,
                thickness: 0.5,
                indent: 20,
                endIndent: 20,
                color: colors.divider,
              ),
              actionTile(
                CupertinoIcons.trash,
                '删除',
                onDelete,
                color: destructive,
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    action?.call();
  }

  @override
  Widget build(BuildContext context) {
    return shadcn.IconButton.ghost(
      icon: Icon(
        CupertinoIcons.ellipsis,
        size: 18,
        color: context.appColors.iconSecondary,
      ),
      onPressed: () => _showActionSheet(context),
    );
  }
}

/// 移动端存储源列表行
class _StorageListTile extends StatelessWidget {
  final Storage storage;
  final VoidCallback onBrowse;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<bool> onToggleEnabled;

  const _StorageListTile({
    required this.storage,
    required this.onBrowse,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleEnabled,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.appColors;
    final type = StorageType.fromString(storage.type);
    final badges = _buildStatusBadges(
      context,
      storage,
      showStreamMode: false,
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onBrowse,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
          child: Row(
            children: [
              _StorageTypeIcon(type: type, enabled: storage.enabled),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      storage.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color:
                            storage.enabled
                                ? colors.textPrimary
                                : colors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _storageShortAddress(storage),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                    if (badges.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(spacing: 6, runSpacing: 4, children: badges),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              CupertinoSwitch(
                value: storage.enabled,
                onChanged: onToggleEnabled,
              ),
              _StorageMoreButton(
                storage: storage,
                onBrowse: onBrowse,
                onEdit: onEdit,
                onDelete: onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 桌面/宽屏存储源卡片
class _StorageCard extends StatefulWidget {
  final Storage storage;
  final VoidCallback onBrowse;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<bool> onToggleEnabled;

  const _StorageCard({
    required this.storage,
    required this.onBrowse,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleEnabled,
  });

  @override
  State<_StorageCard> createState() => _StorageCardState();
}

class _StorageCardState extends State<_StorageCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.appColors;
    final storage = widget.storage;
    final type = StorageType.fromString(storage.type);
    final address = _storageAddress(storage);
    final addressText = Text(
      address ?? '未配置地址',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodySmall?.copyWith(color: colors.textTertiary),
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: colors.cardBackground,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color:
                _hovered
                    ? theme.colorScheme.primary.withValues(alpha: 0.4)
                    : colors.divider,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onBrowse,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _StorageTypeIcon(type: type, enabled: storage.enabled),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              storage.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color:
                                    storage.enabled
                                        ? colors.textPrimary
                                        : colors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                _StatusBadge(
                                  label: type.label,
                                  color:
                                      storage.enabled
                                          ? type.color
                                          : colors.textSecondary,
                                ),
                                ..._buildStatusBadges(
                                  context,
                                  storage,
                                  showStreamMode: true,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      CupertinoSwitch(
                        value: storage.enabled,
                        onChanged: widget.onToggleEnabled,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (address != null)
                    Tooltip(message: address, child: addressText)
                  else
                    addressText,
                  const Spacer(),
                  Divider(height: 1, thickness: 0.5, color: colors.divider),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Tooltip(
                        message: '编辑',
                        child: shadcn.IconButton.ghost(
                          size: shadcn.ButtonSize.small,
                          icon: Icon(
                            CupertinoIcons.pencil,
                            size: 18,
                            color: colors.iconSecondary,
                          ),
                          onPressed: widget.onEdit,
                        ),
                      ),
                      Tooltip(
                        message: '删除',
                        child: shadcn.IconButton.ghost(
                          size: shadcn.ButtonSize.small,
                          icon: Icon(
                            CupertinoIcons.trash,
                            size: 18,
                            color: colors.iconSecondary,
                          ),
                          onPressed: widget.onDelete,
                        ),
                      ),
                      const Spacer(),
                      shadcn.GhostButton(
                        size: shadcn.ButtonSize.small,
                        onPressed: widget.onBrowse,
                        leading: const Icon(CupertinoIcons.folder, size: 16),
                        trailing: const Icon(
                          CupertinoIcons.chevron_right,
                          size: 14,
                        ),
                        child: const Text('浏览'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
