import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_constants.dart';
import '../../core/widgets/dialog_utils.dart';
import '../../providers/version_provider.dart';
import '../../core/widgets/desktop_app_bar.dart';
import '../../core/widgets/mobile_app_bar.dart';
import '../../core/window/window_controls.dart';
import '../../data/services/aria2_manager.dart';
import '../../data/services/update_service.dart';
import '../../providers/aria2_provider.dart';
import '../../providers/providers.dart';
import '../../providers/update_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final themeMode = ref.watch(themeModeProvider);
    final versionAsync = ref.watch(versionProvider);
    final serverState = ref.watch(serverListProvider);
    final currentServer = serverState.currentServer;
    final aria2Config = ref.watch(aria2ConfigProvider);
    final isDesktop = WindowControls.isDesktop;
    final smoothScrollEnabled = isDesktop ? ref.watch(smoothScrollEnabledProvider) : false;

    return Scaffold(
      appBar: isDesktop
          ? DesktopAppBar(
              title: const Text('设置'),
              onBack: () => context.pop(),
            )
          : MobileAppBar(
              title: const Text('设置'),
              onBack: () => context.pop(),
            ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          _buildSectionHeader('服务器', theme),
          _buildSettingsCard(
            isDark,
            children: [
              _buildListTile(
                context, theme, isDark,
                icon: CupertinoIcons.globe,
                iconColor: Colors.blue,
                title: '服务器管理',
                subtitle: currentServer?.name ?? '未配置',
                onTap: () => context.push('/server-config'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildSectionHeader('外观', theme),
          _buildSettingsCard(
            isDark,
            children: [
              _buildListTile(
                context, theme, isDark,
                icon: CupertinoIcons.paintbrush,
                iconColor: Colors.purple,
                title: '主题',
                subtitle: _getThemeModeText(themeMode),
                onTap: () => _showThemeDialog(context, ref, themeMode),
              ),
              if (isDesktop) ...[
                _buildDivider(isDark),
                _buildSwitchTile(
                  theme, isDark,
                  icon: CupertinoIcons.rectangle_on_rectangle_angled,
                  iconColor: Colors.indigo,
                  title: '平滑滚动',
                  value: smoothScrollEnabled,
                  onChanged: (_) => ref.read(smoothScrollEnabledProvider.notifier).toggle(),
                ),
              ],
            ],
          ),
          const SizedBox(height: 24),
          _buildSectionHeader('下载', theme),
          _buildSettingsCard(
            isDark,
            children: [
              _buildListTile(
                context, theme, isDark,
                icon: CupertinoIcons.arrow_down_circle,
                iconColor: Colors.green,
                title: '下载设置',
                subtitle: Aria2Manager.instance.isRunning ? '内置 aria2' : (aria2Config.enabled ? '外部 aria2' : '多线程下载'),
                onTap: () => context.push('/aria2-settings'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildSectionHeader('数据', theme),
          _buildSettingsCard(
            isDark,
            children: [
              _buildListTile(
                context, theme, isDark,
                icon: CupertinoIcons.archivebox,
                iconColor: Colors.orange,
                title: '数据库备份',
                onTap: () => context.push('/database-backup'),
              ),
              _buildDivider(isDark),
              _buildListTile(
                context, theme, isDark,
                icon: CupertinoIcons.folder,
                iconColor: Colors.cyan,
                title: '存储空间',
                onTap: () => context.push('/storage-management'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildSectionHeader('关于', theme),
          _buildSettingsCard(
            isDark,
            children: [
              _buildListTile(
                context, theme, isDark,
                icon: CupertinoIcons.info,
                iconColor: Colors.grey,
                title: '版本',
                subtitle: versionAsync.when(
                  data: (version) => version,
                  loading: () => '...',
                  error: (_, _) => '未知',
                ),
                showChevron: false,
              ),
              if (Platform.isWindows || Platform.isAndroid || Platform.isMacOS) ...[
                _buildDivider(isDark),
                _UpdateCheckTile(isDark: isDark),
              ],
              _buildDivider(isDark),
              _buildListTile(
                context, theme, isDark,
                icon: CupertinoIcons.doc_text,
                iconColor: Colors.teal,
                title: '开源许可',
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: AppConstants.appName,
                  applicationVersion: versionAsync.value ?? '',
                ),
              ),
            ],
          ),
        ],
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
    bool showChevron = true,
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
              if (showChevron && onTap != null) ...[
                const SizedBox(width: 4),
                Icon(
                  CupertinoIcons.chevron_right,
                  size: 16,
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSwitchTile(
    ThemeData theme,
    bool isDark, {
    required IconData icon,
    required Color iconColor,
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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
          CupertinoSwitch(
            value: value,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  String _getThemeModeText(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system:
        return '跟随系统';
      case ThemeMode.light:
        return '浅色';
      case ThemeMode.dark:
        return '深色';
    }
  }

  void _showThemeDialog(
    BuildContext context,
    WidgetRef ref,
    ThemeMode current,
  ) async {
    final selected = await DialogUtils.showSelectionDialog<ThemeMode>(
      context: context,
      title: '选择主题',
      options: [
        SelectionOption(value: ThemeMode.system, label: '跟随系统'),
        SelectionOption(value: ThemeMode.light, label: '浅色'),
        SelectionOption(value: ThemeMode.dark, label: '深色'),
      ],
      currentValue: current,
    );
    if (selected != null) {
      ref.read(themeModeProvider.notifier).setThemeMode(selected);
    }
  }
}

class _UpdateCheckTile extends ConsumerStatefulWidget {
  final bool isDark;
  const _UpdateCheckTile({required this.isDark});

  @override
  ConsumerState<_UpdateCheckTile> createState() => _UpdateCheckTileState();
}

class _UpdateCheckTileState extends ConsumerState<_UpdateCheckTile> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(updateProvider.notifier).checkForUpdate();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final updateState = ref.watch(updateProvider);

    String subtitle;
    bool isLoading = false;
    switch (updateState.status) {
      case UpdateStatus.checking:
        subtitle = '检查中...';
        isLoading = true;
        break;
      case UpdateStatus.available:
        subtitle = '新版本 ${updateState.releaseInfo?.version}';
        break;
      case UpdateStatus.downloading:
        final percent = (updateState.downloadProgress * 100).toStringAsFixed(0);
        subtitle = '下载中 $percent%';
        isLoading = true;
        break;
      case UpdateStatus.installing:
        subtitle = '安装中...';
        isLoading = true;
        break;
      case UpdateStatus.upToDate:
        subtitle = '已是最新版本';
        break;
      case UpdateStatus.error:
        subtitle = '检查失败';
        break;
      default:
        subtitle = '点击检查';
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isLoading ? null : () => _handleTap(updateState),
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
                child: isLoading
                    ? const Padding(
                        padding: EdgeInsets.all(6),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(CupertinoIcons.arrow_clockwise, size: 18, color: Colors.blue),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '检查更新',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Text(
                subtitle,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: updateState.status == UpdateStatus.available
                      ? Colors.blue
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (updateState.status == UpdateStatus.available) ...[
                const SizedBox(width: 4),
                Icon(
                  CupertinoIcons.chevron_right,
                  size: 16,
                  color: widget.isDark ? Colors.grey[400] : Colors.grey[600],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _handleTap(UpdateState updateState) {
    if (updateState.status == UpdateStatus.available) {
      if (Platform.isMacOS) {
        ref.read(updateProvider.notifier).downloadAndInstall();
      } else {
        _showUpdateDialog(updateState.releaseInfo!);
      }
    } else {
      ref.read(updateProvider.notifier).checkForUpdate();
    }
  }

  void _showUpdateDialog(ReleaseInfo info) async {
    final content = info.releaseNotes != null && info.releaseNotes!.isNotEmpty
        ? (info.releaseNotes!.length > 200
            ? '${info.releaseNotes!.substring(0, 200)}...'
            : info.releaseNotes!)
        : '有新版本可用';

    final confirmed = await DialogUtils.showConfirmDialog(
      context: context,
      title: '发现新版本 ${info.version}',
      content: content,
      cancelText: '稍后',
      confirmText: '立即更新',
    );
    if (confirmed == true) {
      ref.read(updateProvider.notifier).downloadAndInstall();
    }
  }
}
