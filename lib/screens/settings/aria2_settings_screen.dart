import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/widgets/desktop_app_bar.dart';
import '../../core/widgets/ios_ui_utils.dart';
import '../../core/widgets/mobile_app_bar.dart';
import '../../core/window/window_controls.dart';
import '../../data/services/aria2_manager.dart';
import '../../data/services/aria2_service.dart';
import '../../providers/aria2_provider.dart';
import '../../providers/download_settings_provider.dart';

enum DownloadEngine { builtin, aria2Builtin, aria2External }

class Aria2SettingsScreen extends ConsumerStatefulWidget {
  const Aria2SettingsScreen({super.key});

  @override
  ConsumerState<Aria2SettingsScreen> createState() => _Aria2SettingsScreenState();
}

class _Aria2SettingsScreenState extends ConsumerState<Aria2SettingsScreen> {
  late TextEditingController _rpcUrlController;
  late TextEditingController _secretController;
  bool _isStarting = false;
  String? _builtinVersion;

  @override
  void initState() {
    super.initState();
    final config = ref.read(aria2ConfigProvider);
    _rpcUrlController = TextEditingController(text: config.rpcUrl);
    _secretController = TextEditingController(text: config.secret);
    _checkBuiltinAria2();
  }

  Future<void> _checkBuiltinAria2() async {
    if (!_isDesktopPlatform) return;
    final aria2 = Aria2Manager.instance;
    if (aria2.isRunning && aria2.service != null) {
      try {
        final version = await aria2.service!.getVersion();
        if (mounted) setState(() => _builtinVersion = version);
      } catch (_) {}
    }
  }

  bool get _isDesktopPlatform => Platform.isWindows || Platform.isMacOS;

  DownloadEngine get _currentEngine {
    final aria2Config = ref.read(aria2ConfigProvider);
    if (Aria2Manager.instance.isRunning) return DownloadEngine.aria2Builtin;
    if (aria2Config.enabled) return DownloadEngine.aria2External;
    return DownloadEngine.builtin;
  }

  @override
  void dispose() {
    _rpcUrlController.dispose();
    _secretController.dispose();
    super.dispose();
  }

  Future<void> _selectEngine(DownloadEngine engine) async {
    switch (engine) {
      case DownloadEngine.builtin:
        await Aria2Manager.instance.stop();
        ref.read(aria2ConfigProvider.notifier).setEnabled(false);
        setState(() => _builtinVersion = null);
        break;
      case DownloadEngine.aria2Builtin:
        ref.read(aria2ConfigProvider.notifier).setEnabled(false);
        await _startBuiltinAria2();
        break;
      case DownloadEngine.aria2External:
        // 先验证外部 aria2 连接
        final config = ref.read(aria2ConfigProvider);
        final valid = await _verifyExternalAria2(config.rpcUrl, config.secret);
        if (!valid) {
          // 验证失败，弹出配置弹框
          if (mounted) await _showExternalAria2ConfigDialog();
          return;
        }
        await Aria2Manager.instance.stop();
        setState(() => _builtinVersion = null);
        ref.read(aria2ConfigProvider.notifier).setEnabled(true);
        break;
    }
  }

  Future<void> _showExternalAria2ConfigDialog() async {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    bool isConnecting = false;
    String? errorMsg;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(context).viewInsets.bottom + 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[400],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '配置外部 aria2',
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 20),
                Text('RPC 地址', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                TextField(
                  controller: _rpcUrlController,
                  decoration: InputDecoration(
                    hintText: 'http://localhost:6800/jsonrpc',
                    filled: true,
                    fillColor: isDark ? Colors.grey[900] : Colors.grey[100],
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  ),
                ),
                const SizedBox(height: 16),
                Text('RPC 密钥（可选）', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                TextField(
                  controller: _secretController,
                  decoration: InputDecoration(
                    hintText: '留空表示无密钥',
                    filled: true,
                    fillColor: isDark ? Colors.grey[900] : Colors.grey[100],
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  ),
                ),
                if (errorMsg != null) ...[
                  const SizedBox(height: 12),
                  Text(errorMsg!, style: TextStyle(color: Colors.red[400], fontSize: 13)),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: CupertinoButton.filled(
                    onPressed: isConnecting
                        ? null
                        : () async {
                            setDialogState(() {
                              isConnecting = true;
                              errorMsg = null;
                            });
                            await _saveConfig();
                            final valid = await _verifyExternalAria2(
                              _rpcUrlController.text.trim(),
                              _secretController.text.trim(),
                            );
                            if (valid) {
                              if (mounted) Navigator.pop(context);
                              await Aria2Manager.instance.stop();
                              setState(() => _builtinVersion = null);
                              ref.read(aria2ConfigProvider.notifier).setEnabled(true);
                              if (mounted) {
                                IosUiUtils.showToast(context: context, message: '已切换到外部 aria2');
                              }
                            } else {
                              setDialogState(() {
                                isConnecting = false;
                                errorMsg = '连接失败，请检查地址和密钥是否正确';
                              });
                            }
                          },
                    child: isConnecting
                        ? const CupertinoActivityIndicator(color: Colors.white)
                        : const Text('连接'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<bool> _verifyExternalAria2(String rpcUrl, String? secret) async {
    if (rpcUrl.isEmpty) {
      return false;
    }
    try {
      final service = Aria2Service(
        rpcUrl: rpcUrl,
        secret: secret?.isNotEmpty == true ? secret : null,
      );
      await service.getVersion();
      service.dispose();
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<void> _startBuiltinAria2() async {
    setState(() => _isStarting = true);
    try {
      final aria2 = Aria2Manager.instance;
      if (!await aria2.isAvailable()) {
        if (mounted) {
          IosUiUtils.showToast(context: context, message: 'aria2 不可用', isError: true);
        }
        setState(() => _isStarting = false);
        return;
      }
      await aria2.start();
      final version = await aria2.service!.getVersion();
      if (mounted) {
        setState(() {
          _builtinVersion = version;
          _isStarting = false;
        });
        IosUiUtils.showToast(context: context, message: 'aria2 已启动 (v$version)');
      }
    } catch (e) {
      if (mounted) {
        IosUiUtils.showToast(context: context, message: '启动失败: $e', isError: true);
        setState(() => _isStarting = false);
      }
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
    final downloadSettings = ref.watch(downloadSettingsProvider);
    final isDesktop = WindowControls.isDesktop;
    final currentEngine = _currentEngine;

    return Scaffold(
      appBar: isDesktop
          ? DesktopAppBar(title: const Text('下载设置'), onBack: () => context.pop())
          : MobileAppBar(title: const Text('下载设置'), onBack: () => context.pop()),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          // 当前状态
          _buildSectionHeader('当前下载引擎', theme),
          _buildCurrentEngineCard(theme, isDark, currentEngine),

          // 引擎选择
          const SizedBox(height: 24),
          _buildSectionHeader('选择下载引擎', theme),
          _buildSettingsCard(isDark, children: [
            _buildEngineOption(
              theme, isDark,
              engine: DownloadEngine.builtin,
              currentEngine: currentEngine,
              icon: CupertinoIcons.bolt,
              iconColor: Colors.orange,
              title: '内置多线程',
              subtitle: '适用于所有平台',
            ),
            if (_isDesktopPlatform)
              _buildEngineOption(
                theme, isDark,
                engine: DownloadEngine.aria2Builtin,
                currentEngine: currentEngine,
                icon: CupertinoIcons.arrow_down_circle,
                iconColor: Colors.green,
                title: '内置 aria2',
                subtitle: _isStarting ? '启动中...' : (_builtinVersion != null ? '运行中 v$_builtinVersion' : '推荐，性能更好'),
                isLoading: _isStarting,
              ),
            _buildEngineOption(
              theme, isDark,
              engine: DownloadEngine.aria2External,
              currentEngine: currentEngine,
              icon: CupertinoIcons.link,
              iconColor: Colors.blue,
              title: '外部 aria2',
              subtitle: '连接已运行的 aria2 服务',
            ),
          ]),

          // 引擎配置
          const SizedBox(height: 24),
          if (currentEngine == DownloadEngine.builtin) ...[
            _buildSectionHeader('多线程配置', theme),
            _buildSettingsCard(isDark, children: [
              _buildListTile(
                context, theme, isDark,
                icon: CupertinoIcons.number,
                iconColor: Colors.purple,
                title: '下载线程数',
                subtitle: '${downloadSettings.threadCount} 线程',
                onTap: () => _showThreadCountPicker(context, downloadSettings.threadCount),
              ),
            ]),
          ],
        ],
      ),
    );
  }

  Widget _buildCurrentEngineCard(ThemeData theme, bool isDark, DownloadEngine engine) {
    String name;
    String status;
    Color color;
    IconData icon;

    switch (engine) {
      case DownloadEngine.builtin:
        name = '内置多线程';
        status = '使用中';
        color = Colors.orange;
        icon = CupertinoIcons.bolt;
        break;
      case DownloadEngine.aria2Builtin:
        name = '内置 aria2';
        status = _builtinVersion != null ? 'v$_builtinVersion 运行中' : '使用中';
        color = Colors.green;
        icon = CupertinoIcons.arrow_down_circle;
        break;
      case DownloadEngine.aria2External:
        name = '外部 aria2';
        status = '使用中';
        color = Colors.blue;
        icon = CupertinoIcons.link;
        break;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                Text(status, style: theme.textTheme.bodySmall?.copyWith(color: color)),
              ],
            ),
          ),
          Icon(CupertinoIcons.checkmark_circle_fill, color: color, size: 24),
        ],
      ),
    );
  }

  Widget _buildEngineOption(
    ThemeData theme,
    bool isDark, {
    required DownloadEngine engine,
    required DownloadEngine currentEngine,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    bool isLoading = false,
  }) {
    final isSelected = engine == currentEngine;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isLoading ? null : () => _selectEngine(engine),
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
                    Text(title, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500)),
                    Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
              if (isLoading)
                const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              else if (isSelected)
                const Icon(CupertinoIcons.checkmark_circle_fill, color: Colors.green, size: 22)
              else
                Icon(CupertinoIcons.circle, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3), size: 22),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.w500),
      ),
    );
  }

  Widget _buildSettingsCard(bool isDark, {required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(color: isDark ? const Color(0xFF1C1C1E) : Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Column(children: children),
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
                decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                child: Icon(icon, size: 18, color: iconColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500)),
                    if (subtitle != null)
                      Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
              Icon(CupertinoIcons.chevron_right, size: 16, color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
