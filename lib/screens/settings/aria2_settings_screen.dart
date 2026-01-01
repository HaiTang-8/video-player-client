import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/widgets/desktop_app_bar.dart';
import '../../core/widgets/ios_ui_utils.dart';
import '../../core/widgets/mobile_app_bar.dart';
import '../../core/window/window_controls.dart';
import '../../data/services/aria2_service.dart';
import '../../providers/aria2_provider.dart';
import '../../providers/download_settings_provider.dart';

class Aria2SettingsScreen extends ConsumerStatefulWidget {
  const Aria2SettingsScreen({super.key});

  @override
  ConsumerState<Aria2SettingsScreen> createState() => _Aria2SettingsScreenState();
}

class _Aria2SettingsScreenState extends ConsumerState<Aria2SettingsScreen> {
  late TextEditingController _rpcUrlController;
  late TextEditingController _secretController;
  bool _isTesting = false;

  @override
  void initState() {
    super.initState();
    final config = ref.read(aria2ConfigProvider);
    _rpcUrlController = TextEditingController(text: config.rpcUrl);
    _secretController = TextEditingController(text: config.secret);
  }

  @override
  void dispose() {
    _rpcUrlController.dispose();
    _secretController.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    setState(() => _isTesting = true);
    try {
      final service = Aria2Service(
        rpcUrl: _rpcUrlController.text.trim(),
        secret: _secretController.text.trim().isNotEmpty ? _secretController.text.trim() : null,
      );
      final version = await service.getVersion();
      service.dispose();
      if (mounted) {
        IosUiUtils.showToast(
          context: context,
          message: '连接成功，aria2 版本: $version',
        );
      }
    } catch (e) {
      if (mounted) {
        IosUiUtils.showToast(
          context: context,
          message: '连接失败: $e',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _isTesting = false);
    }
  }

  Future<void> _saveConfig() async {
    final notifier = ref.read(aria2ConfigProvider.notifier);
    await notifier.updateConfig(
      rpcUrl: _rpcUrlController.text.trim(),
      secret: _secretController.text.trim(),
    );
  }

  void _showThreadCountPicker(BuildContext context, int currentCount) {
    final options = [1, 2, 4, 8, 16, 32];
    showCupertinoModalPopup(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('选择下载线程数'),
        message: const Text('线程数越多下载越快，但会占用更多资源'),
        actions: options.map((count) {
          return CupertinoActionSheetAction(
            onPressed: () {
              ref.read(downloadSettingsProvider.notifier).setThreadCount(count);
              Navigator.pop(context);
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('$count 线程'),
                if (count == currentCount)
                  const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: Icon(CupertinoIcons.checkmark, size: 18, color: Colors.blue),
                  ),
              ],
            ),
          );
        }).toList(),
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final aria2Config = ref.watch(aria2ConfigProvider);
    final downloadSettings = ref.watch(downloadSettingsProvider);
    final isDesktop = WindowControls.isDesktop;

    return Scaffold(
      appBar: isDesktop
          ? DesktopAppBar(
              title: const Text('下载设置'),
              onBack: () => context.pop(),
            )
          : MobileAppBar(
              title: const Text('下载设置'),
              onBack: () => context.pop(),
            ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          // 多线程下载设置
          _buildSectionHeader('内置下载器', theme),
          _buildSettingsCard(
            isDark,
            children: [
              _buildSwitchTile(
                theme,
                isDark,
                icon: CupertinoIcons.bolt,
                iconColor: Colors.orange,
                title: '多线程下载',
                subtitle: '使用多线程加速下载',
                value: downloadSettings.multiThreadEnabled,
                onChanged: (value) {
                  ref.read(downloadSettingsProvider.notifier).setMultiThreadEnabled(value);
                },
              ),
              if (downloadSettings.multiThreadEnabled) ...[
                const Divider(height: 1, indent: 56),
                _buildListTile(
                  context,
                  theme,
                  isDark,
                  icon: CupertinoIcons.number,
                  iconColor: Colors.purple,
                  title: '下载线程数',
                  subtitle: '${downloadSettings.threadCount} 线程',
                  onTap: () => _showThreadCountPicker(context, downloadSettings.threadCount),
                ),
              ],
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
            child: Text(
              '多线程下载可以显著提升下载速度，适用于支持 Range 请求的服务器',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),

          // aria2 设置
          const SizedBox(height: 24),
          _buildSectionHeader('aria2 下载器 (可选)', theme),
          _buildSettingsCard(
            isDark,
            children: [
              _buildSwitchTile(
                theme,
                isDark,
                icon: CupertinoIcons.arrow_down_circle,
                iconColor: Colors.green,
                title: '启用 aria2',
                subtitle: '使用外部 aria2 程序下载',
                value: aria2Config.enabled,
                onChanged: (value) {
                  ref.read(aria2ConfigProvider.notifier).setEnabled(value);
                },
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
            child: Text(
              'aria2 是一个轻量级的命令行下载工具，需要单独安装',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),

          if (aria2Config.enabled) ...[
            const SizedBox(height: 24),
            _buildSectionHeader('aria2 RPC 配置', theme),
            _buildSettingsCard(
              isDark,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'RPC 地址',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _rpcUrlController,
                        decoration: InputDecoration(
                          hintText: 'http://localhost:6800/jsonrpc',
                          filled: true,
                          fillColor: isDark ? Colors.grey[900] : Colors.grey[100],
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                        ),
                        onChanged: (_) => _saveConfig(),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'RPC 密钥 (Secret)',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _secretController,
                        obscureText: true,
                        decoration: InputDecoration(
                          hintText: '留空表示无密钥',
                          filled: true,
                          fillColor: isDark ? Colors.grey[900] : Colors.grey[100],
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                        ),
                        onChanged: (_) => _saveConfig(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildSettingsCard(
              isDark,
              children: [
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _isTesting ? null : _testConnection,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (_isTesting)
                            const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          else
                            const Icon(CupertinoIcons.wifi, size: 18, color: Colors.blue),
                          const SizedBox(width: 8),
                          Text(
                            _isTesting ? '测试中...' : '测试连接',
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: Colors.blue,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 16, 4, 0),
              child: Text(
                '启动命令示例：\naria2c --enable-rpc --rpc-listen-all --rpc-secret=YOUR_SECRET',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
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

  Widget _buildSwitchTile(
    ThemeData theme,
    bool isDark, {
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          CupertinoSwitch(
            value: value,
            onChanged: onChanged,
            activeTrackColor: Colors.green,
          ),
        ],
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
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle,
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
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
