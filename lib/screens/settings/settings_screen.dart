import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/widgets/app_back_button.dart';
import '../../core/widgets/desktop_title_bar.dart';
import '../../core/widgets/ios_ui_utils.dart';
import '../../core/window/window_controls.dart';
import '../../providers/providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final themeMode = ref.watch(themeModeProvider);
    final serverUrl = ref.watch(serverUrlProvider);
    final isDesktop = WindowControls.isDesktop;

    return Scaffold(
      appBar: isDesktop
          ? DesktopTitleBar(
              leading: AppBackButton(onPressed: () => context.pop()),
              title: const Text('设置'),
              centerTitle: false,
            )
          : AppBar(
              centerTitle: false,
              automaticallyImplyLeading: false,
              leadingWidth: kAppBackButtonWidth,
              titleSpacing: 1,
              leading: AppBackButton(onPressed: () => context.pop()),
              title: const Text('设置'),
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
                title: '服务器地址',
                subtitle: serverUrl ?? '未配置',
                onTap: () => _showServerDialog(context, ref, serverUrl),
              ),
              _buildDivider(isDark),
              _buildListTile(
                context, theme, isDark,
                icon: CupertinoIcons.folder,
                iconColor: Colors.orange,
                title: '存储源管理',
                onTap: () => context.push('/storage-manage'),
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
                subtitle: '1.0.0',
                showChevron: false,
              ),
              _buildDivider(isDark),
              _buildListTile(
                context, theme, isDark,
                icon: CupertinoIcons.doc_text,
                iconColor: Colors.teal,
                title: '开源许可',
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: 'Media Player',
                  applicationVersion: '1.0.0',
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
  ) {
    showCupertinoModalPopup<ThemeMode>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('选择主题'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context, ThemeMode.system),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('跟随系统'),
                if (current == ThemeMode.system) ...[
                  const SizedBox(width: 8),
                  const Icon(CupertinoIcons.checkmark_alt, size: 18),
                ],
              ],
            ),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context, ThemeMode.light),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('浅色'),
                if (current == ThemeMode.light) ...[
                  const SizedBox(width: 8),
                  const Icon(CupertinoIcons.checkmark_alt, size: 18),
                ],
              ],
            ),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context, ThemeMode.dark),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('深色'),
                if (current == ThemeMode.dark) ...[
                  const SizedBox(width: 8),
                  const Icon(CupertinoIcons.checkmark_alt, size: 18),
                ],
              ],
            ),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ),
    ).then((value) {
      if (value != null) {
        ref.read(themeModeProvider.notifier).setThemeMode(value);
      }
    });
  }

  void _showServerDialog(BuildContext context, WidgetRef ref, String? current) {
    final controller = TextEditingController(text: current);

    showCupertinoDialog<void>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('服务器地址'),
        content: Padding(
          padding: const EdgeInsets.only(top: 16),
          child: CupertinoTextField(
            controller: controller,
            placeholder: 'http://192.168.1.100:8080',
            keyboardType: TextInputType.url,
            autofocus: true,
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            onPressed: () async {
              final url = controller.text.trim();
              if (url.isNotEmpty) {
                final success = await ref
                    .read(serverConnectionProvider.notifier)
                    .testConnection(url);
                if (success) {
                  await ref
                      .read(serverUrlProvider.notifier)
                      .setServerUrl(url);
                  if (context.mounted) {
                    Navigator.pop(context);
                    IosUiUtils.showToast(
                      context: context,
                      message: '服务器连接成功',
                    );
                  }
                } else {
                  if (context.mounted) {
                    IosUiUtils.showToast(
                      context: context,
                      message: '无法连接到服务器',
                      isError: true,
                    );
                  }
                }
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }
}
