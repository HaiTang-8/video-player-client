import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/widgets/desktop_app_bar.dart';
import '../../core/widgets/ios_ui_utils.dart';
import '../../core/widgets/mobile_app_bar.dart';
import '../../core/widgets/skeleton_loader.dart';
import '../../core/window/window_controls.dart';
import '../../providers/providers.dart';

class DatabaseBackupScreen extends ConsumerStatefulWidget {
  const DatabaseBackupScreen({super.key});

  @override
  ConsumerState<DatabaseBackupScreen> createState() =>
      _DatabaseBackupScreenState();
}

class _DatabaseBackupScreenState extends ConsumerState<DatabaseBackupScreen> {
  bool _isCreating = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(databaseBackupsProvider.notifier).loadBackups(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isDesktop = WindowControls.isDesktop;
    final backupsAsync = ref.watch(databaseBackupsProvider);

    return Scaffold(
      appBar:
          isDesktop
              ? DesktopAppBar(
                title: const Text('数据库备份'),
                onBack: () => context.pop(),
              )
              : MobileAppBar(
                title: const Text('数据库备份'),
                onBack: () => context.pop(),
              ),
      body: backupsAsync.when(
        loading: () => const ListSkeletonLoader(),
        error:
            (error, _) => AppErrorWidget(
              message: error.toString(),
              onRetry:
                  () =>
                      ref.read(databaseBackupsProvider.notifier).loadBackups(),
            ),
        data:
            (backups) => ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                _buildSectionHeader('操作', theme),
                _buildSettingsCard(
                  isDark,
                  children: [
                    _buildListTile(
                      context,
                      theme,
                      isDark,
                      icon: CupertinoIcons.add_circled,
                      iconColor: Colors.green,
                      title: '创建备份',
                      subtitle: _isCreating ? '创建中...' : null,
                      onTap: _isCreating ? null : _createBackup,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _buildSectionHeader('备份列表 (${backups.length})', theme),
                if (backups.isEmpty)
                  _buildSettingsCard(
                    isDark,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(32),
                        child: Center(
                          child: Text(
                            '暂无备份',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                else
                  _buildSettingsCard(
                    isDark,
                    children: [
                      for (int i = 0; i < backups.length; i++) ...[
                        if (i > 0) _buildDivider(isDark),
                        _buildBackupTile(context, theme, isDark, backups[i]),
                      ],
                    ],
                  ),
              ],
            ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildSettingsCard(bool isDark, {required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(children: children),
    );
  }

  Widget _buildDivider(bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(left: 60),
      child: Divider(
        height: 1,
        color: isDark ? Colors.grey[800] : Colors.grey[200],
      ),
    );
  }

  Widget _buildListTile(
    BuildContext context,
    ThemeData theme,
    bool isDark, {
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 18, color: iconColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (subtitle != null)
                Text(
                  subtitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBackupTile(
    BuildContext context,
    ThemeData theme,
    bool isDark,
    dynamic backup,
  ) {
    final dateFormat = DateFormat('yyyy-MM-dd HH:mm');
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showBackupActions(context, backup),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  CupertinoIcons.doc,
                  size: 18,
                  color: Colors.blue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      backup.name,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      '${dateFormat.format(backup.createdAt)} · ${backup.formattedSize}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                CupertinoIcons.chevron_right,
                size: 16,
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _createBackup() async {
    setState(() => _isCreating = true);
    final success =
        await ref.read(databaseBackupsProvider.notifier).createBackup();
    if (mounted) {
      setState(() => _isCreating = false);
      IosUiUtils.showToast(
        context: context,
        message: success ? '备份创建成功' : '备份创建失败',
        isError: !success,
      );
    }
  }

  void _showBackupActions(BuildContext context, dynamic backup) {
    showCupertinoModalPopup<void>(
      context: context,
      builder:
          (context) => CupertinoActionSheet(
            title: Text(backup.name),
            actions: [
              CupertinoActionSheetAction(
                isDestructiveAction: true,
                onPressed: () {
                  Navigator.pop(context);
                  _confirmRollback(backup);
                },
                child: const Text('回滚到此备份'),
              ),
              CupertinoActionSheetAction(
                isDestructiveAction: true,
                onPressed: () {
                  Navigator.pop(context);
                  _confirmDelete(backup);
                },
                child: const Text('删除备份'),
              ),
            ],
            cancelButton: CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
          ),
    );
  }

  Future<void> _confirmDelete(dynamic backup) async {
    final confirmed = await IosUiUtils.showConfirmDialog(
      context: context,
      title: '确认删除',
      content: '确定要删除备份 ${backup.name} 吗？此操作不可恢复。',
      confirmText: '删除',
      isDestructive: true,
    );
    if (confirmed == true && mounted) {
      final success = await ref
          .read(databaseBackupsProvider.notifier)
          .deleteBackup(backup.name);
      if (mounted) {
        IosUiUtils.showToast(
          context: context,
          message: success ? '备份已删除' : '删除失败',
          isError: !success,
        );
      }
    }
  }

  Future<void> _confirmRollback(dynamic backup) async {
    final confirmed = await IosUiUtils.showConfirmDialog(
      context: context,
      title: '确认回滚',
      content: '回滚将替换当前数据库，服务器会自动重启。确定要回滚到 ${backup.name} 吗？',
      confirmText: '回滚',
      isDestructive: true,
    );
    if (confirmed == true && mounted) {
      final success = await ref
          .read(databaseBackupsProvider.notifier)
          .rollback(backup.name);
      if (mounted) {
        IosUiUtils.showToast(
          context: context,
          message: success ? '回滚成功，服务器即将重启' : '回滚失败',
          isError: !success,
        );
      }
    }
  }
}
