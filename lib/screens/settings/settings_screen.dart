import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/widgets/app_back_button.dart';
import '../../core/widgets/desktop_title_bar.dart';
import '../../core/widgets/ios_ui_utils.dart';
import '../../core/window/window_controls.dart';
import '../../providers/providers.dart';

/// 设置页面
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final themeMode = ref.watch(themeModeProvider);
    final serverUrl = ref.watch(serverUrlProvider);
    final isDesktop = WindowControls.isDesktop;

    return Scaffold(
      appBar:
          isDesktop
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
        children: [
          // 服务器设置
          _buildSectionHeader('服务器', theme),
          ListTile(
            leading: const Icon(Icons.dns_outlined),
            title: const Text('服务器地址'),
            subtitle: Text(serverUrl ?? '未配置'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showServerDialog(context, ref, serverUrl),
          ),
          ListTile(
            leading: const Icon(Icons.storage_outlined),
            title: const Text('存储源管理'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/storage-manage'),
          ),
          const Divider(),

          // 外观设置
          _buildSectionHeader('外观', theme),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('主题'),
            subtitle: Text(_getThemeModeText(themeMode)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showThemeDialog(context, ref, themeMode),
          ),
          const Divider(),

          // 关于
          _buildSectionHeader('关于', theme),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('版本'),
            subtitle: const Text('1.0.0'),
          ),
          ListTile(
            leading: const Icon(Icons.code),
            title: const Text('开源许可'),
            trailing: const Icon(Icons.chevron_right),
            onTap:
                () => showLicensePage(
                  context: context,
                  applicationName: 'Media Player',
                  applicationVersion: '1.0.0',
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.bold,
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
