import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/app_constants.dart';
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
  Timer? _refreshTimer;
  Map<String, dynamic>? _globalStat;
  List<Map<String, dynamic>> _activeTasks = [];
  int _waitingCount = 0;
  int _stoppedCount = 0;

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
        if (mounted) {
          setState(() => _builtinVersion = version);
          _startRefreshTimer();
        }
      } catch (_) {}
    }
  }

  void _startRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshAria2Status();
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (_) => _refreshAria2Status());
  }

  void _stopRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  Future<void> _refreshAria2Status() async {
    final aria2 = Aria2Manager.instance;
    if (!aria2.isRunning || aria2.service == null) return;
    try {
      final stat = await aria2.service!.getGlobalStat();
      final active = await aria2.service!.tellActive();
      final waiting = await aria2.service!.tellWaiting(0, 100);
      final stopped = await aria2.service!.tellStopped(0, 100);
      if (mounted) {
        setState(() {
          _globalStat = stat;
          _activeTasks = active;
          _waitingCount = waiting.length;
          _stoppedCount = stopped.length;
        });
      }
    } catch (_) {}
  }

  bool get _isDesktopPlatform => Platform.isWindows || Platform.isMacOS;

  DownloadEngine get _currentEngine {
    if (Aria2Manager.instance.isRunning) return DownloadEngine.aria2Builtin;
    final aria2Config = ref.read(aria2ConfigProvider);
    if (aria2Config.enabled) return DownloadEngine.aria2External;
    return DownloadEngine.builtin;
  }

  @override
  void dispose() {
    _stopRefreshTimer();
    _rpcUrlController.dispose();
    _secretController.dispose();
    super.dispose();
  }

  Future<void> _selectEngine(DownloadEngine engine) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.downloadEngineKey, engine.name);

    switch (engine) {
      case DownloadEngine.builtin:
        _stopRefreshTimer();
        await Aria2Manager.instance.stop();
        ref.read(aria2ConfigProvider.notifier).setEnabled(false);
        setState(() {
          _builtinVersion = null;
          _globalStat = null;
          _activeTasks = [];
          _waitingCount = 0;
          _stoppedCount = 0;
        });
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
        _stopRefreshTimer();
        await Aria2Manager.instance.stop();
        setState(() {
          _builtinVersion = null;
          _globalStat = null;
          _activeTasks = [];
          _waitingCount = 0;
          _stoppedCount = 0;
        });
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
        _startRefreshTimer();
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
          if (currentEngine == DownloadEngine.aria2Builtin && _builtinVersion != null) ...[
            _buildAria2StatusPanel(theme, isDark),
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

  Widget _buildAria2StatusPanel(ThemeData theme, bool isDark) {
    final aria2 = Aria2Manager.instance;
    final downloadSpeed = int.tryParse(_globalStat?['downloadSpeed'] ?? '0') ?? 0;
    final uploadSpeed = int.tryParse(_globalStat?['uploadSpeed'] ?? '0') ?? 0;
    final numActive = int.tryParse(_globalStat?['numActive'] ?? '0') ?? 0;

    Widget buildBentoCard(IconData icon, Color color, String label, String value) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(height: 12),
              Text(
                value,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()]),
              ),
              const SizedBox(height: 2),
              Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('运行状态', theme),
        Row(
          children: [
            buildBentoCard(CupertinoIcons.info, Colors.blue, '版本', 'v$_builtinVersion'),
            const SizedBox(width: 12),
            buildBentoCard(CupertinoIcons.antenna_radiowaves_left_right, Colors.purple, '端口', '${aria2.rpcPort}'),
            const SizedBox(width: 12),
            buildBentoCard(CupertinoIcons.clock, Colors.orange, '运行时长', _formatUptime(aria2.startTime)),
          ],
        ),

        const SizedBox(height: 24),
        _buildSectionHeader('传输统计', theme),
        Row(
          children: [
            buildBentoCard(CupertinoIcons.arrow_down, Colors.green, '下载', _formatSpeed(downloadSpeed)),
            const SizedBox(width: 12),
            buildBentoCard(CupertinoIcons.arrow_up, Colors.blue, '上传', _formatSpeed(uploadSpeed)),
          ],
        ),

        const SizedBox(height: 24),
        _buildSectionHeader('任务概览', theme),
        Row(
          children: [
            buildBentoCard(CupertinoIcons.play_fill, Colors.green, '活动', '$numActive'),
            const SizedBox(width: 12),
            buildBentoCard(CupertinoIcons.clock_fill, Colors.orange, '等待', '$_waitingCount'),
            const SizedBox(width: 12),
            buildBentoCard(CupertinoIcons.stop_fill, Colors.grey, '已停止', '$_stoppedCount'),
          ],
        ),

        if (_activeTasks.isNotEmpty) ...[
          const SizedBox(height: 24),
          _buildSectionHeader('活动任务', theme),
          _buildSettingsCard(isDark, children: [
            for (var i = 0; i < _activeTasks.length; i++) ...[
              if (i > 0) Divider(height: 1, indent: 16, endIndent: 16, color: theme.dividerColor),
              _buildActiveTaskItem(theme, _activeTasks[i]),
            ],
          ]),
        ],
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildActiveTaskItem(ThemeData theme, Map<String, dynamic> task) {
    final files = task['files'] as List?;
    String filename = '未知文件';
    if (files != null && files.isNotEmpty) {
      final path = files[0]['path'] as String? ?? '';
      filename = path.split('/').last.split('\\').last;
      if (filename.isEmpty) filename = '未知文件';
    }
    final totalLength = int.tryParse(task['totalLength'] ?? '0') ?? 0;
    final completedLength = int.tryParse(task['completedLength'] ?? '0') ?? 0;
    final downloadSpeed = int.tryParse(task['downloadSpeed'] ?? '0') ?? 0;
    final progress = totalLength > 0 ? completedLength / totalLength : 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            filename,
            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 4,
              backgroundColor: theme.dividerColor,
              valueColor: const AlwaysStoppedAnimation(Colors.green),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${_formatSize(completedLength)} / ${_formatSize(totalLength)}',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              Text(
                _formatSpeed(downloadSpeed),
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.green),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatUptime(DateTime? startTime) {
    if (startTime == null) return '-';
    final duration = DateTime.now().difference(startTime);
    if (duration.inHours > 0) {
      return '${duration.inHours}小时${duration.inMinutes % 60}分钟';
    } else if (duration.inMinutes > 0) {
      return '${duration.inMinutes}分钟';
    }
    return '${duration.inSeconds}秒';
  }

  String _formatSpeed(int bytesPerSecond) {
    if (bytesPerSecond < 1024) return '$bytesPerSecond B/s';
    if (bytesPerSecond < 1024 * 1024) return '${(bytesPerSecond / 1024).toStringAsFixed(1)} KB/s';
    return '${(bytesPerSecond / 1024 / 1024).toStringAsFixed(1)} MB/s';
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }
}
