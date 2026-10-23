import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/widgets/desktop_app_bar.dart';
import '../../core/widgets/mobile_app_bar.dart';
import '../../core/window/window_controls.dart';
import '../../data/services/storage_management_service.dart';
import '../../playback/cache/playback_cache_catalog.dart';
import '../../playback/domain/engine_preference.dart';
import '../../playback/playback_providers.dart';
import '../../providers/providers.dart';

class PlaybackSettingsScreen extends ConsumerWidget {
  const PlaybackSettingsScreen({super.key});

  static const _speedOptions = [
    0.25,
    0.5,
    0.75,
    1.0,
    1.25,
    1.5,
    1.75,
    2.0,
    2.5,
    3.0,
  ];

  static const _enginePreferenceDescriptions = {
    EnginePreference.auto: '优先使用系统解码，支持杜比视界和 HDR；无法播放时自动切换到兼容内核',
    EnginePreference.compatibility: '始终使用 mpv，格式和特效字幕兼容性最好，但不支持杜比视界和 HDR 输出',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDesktop = WindowControls.isDesktop;
    final isDark = theme.brightness == Brightness.dark;
    final settings = ref.watch(playbackSettingsProvider);

    return Scaffold(
      appBar:
          isDesktop
              ? DesktopAppBar(
                title: const Text('播放设置'),
                onBack: () => context.pop(),
              )
              : MobileAppBar(
                title: const Text('播放设置'),
                onBack: () => context.pop(),
              ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          _buildSectionHeader('快进/快退', theme),
          _buildSettingsCard(
            isDark,
            children: [
              _buildListTile(
                context,
                theme,
                isDark,
                icon: CupertinoIcons.forward_end,
                iconColor: Colors.orange,
                title: '时长',
                subtitle: '${settings.seekDuration}秒',
                onTap:
                    () => _showSeekDurationPicker(
                      context,
                      ref,
                      settings.seekDuration,
                    ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
            child: Text(
              '设置每次快进或快退的时长（1-60秒）',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 24),
          _buildSectionHeader('播放速度', theme),
          _buildSettingsCard(
            isDark,
            children: [
              _buildListTile(
                context,
                theme,
                isDark,
                icon: CupertinoIcons.speedometer,
                iconColor: Colors.blue,
                title: '默认速度',
                subtitle: '${settings.playbackSpeed}x',
                onTap:
                    () => _showSpeedPicker(
                      context,
                      ref,
                      title: '默认速度',
                      current: settings.playbackSpeed,
                      onSelected:
                          (speed) => ref
                              .read(playbackSettingsProvider.notifier)
                              .setPlaybackSpeed(speed),
                    ),
              ),
              Divider(
                height: 1,
                indent: 60,
                color: theme.dividerColor.withValues(alpha: 0.3),
              ),
              _buildListTile(
                context,
                theme,
                isDark,
                icon: CupertinoIcons.speedometer,
                iconColor: Colors.purple,
                title: '长按倍速',
                subtitle: '${settings.longPressSpeed}x',
                onTap:
                    () => _showSpeedPicker(
                      context,
                      ref,
                      title: '长按倍速',
                      current: settings.longPressSpeed,
                      onSelected:
                          (speed) => ref
                              .read(playbackSettingsProvider.notifier)
                              .setLongPressSpeed(speed),
                    ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
            child: Text(
              '设置默认播放速度和长按临时倍速',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (ref.watch(enginePreferenceAvailableProvider)) ...[
            const SizedBox(height: 24),
            _buildSectionHeader('播放内核', theme),
            _buildSettingsCard(
              isDark,
              children: [
                _buildListTile(
                  context,
                  theme,
                  isDark,
                  icon: CupertinoIcons.play_rectangle,
                  iconColor: Colors.teal,
                  title: '内核偏好',
                  subtitle: settings.enginePreference.label,
                  onTap:
                      () => _showEnginePreferencePicker(
                        context,
                        ref,
                        settings.enginePreference,
                      ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
              child: Text(
                '遇到无法播放或画面、声音异常时可切换到兼容模式，下次打开视频时生效',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
          if (ref.watch(playbackCacheSupportedProvider))
            const _PlaybackCacheSection(),
        ],
      ),
    );
  }

  static Widget _buildSectionHeader(String title, ThemeData theme) {
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

  static Widget _buildSettingsCard(
    bool isDark, {
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(children: children),
    );
  }

  static Widget _buildListTile(
    BuildContext context,
    ThemeData theme,
    bool isDark, {
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
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
              Text(
                subtitle,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 4),
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

  void _showSeekDurationPicker(
    BuildContext context,
    WidgetRef ref,
    int current,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    int selected = current;

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder:
          (context) => StatefulBuilder(
            builder:
                (context, setState) => SizedBox(
                  height: 300,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            CupertinoButton(
                              child: Text(
                                '取消',
                                style: TextStyle(
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                              onPressed: () => Navigator.pop(context),
                            ),
                            Text(
                              '快进/快退时长',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            CupertinoButton(
                              child: Text(
                                '完成',
                                style: TextStyle(
                                  color: theme.colorScheme.primary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              onPressed: () {
                                ref
                                    .read(playbackSettingsProvider.notifier)
                                    .setSeekDuration(selected);
                                Navigator.pop(context);
                              },
                            ),
                          ],
                        ),
                      ),
                      Divider(
                        height: 1,
                        color: theme.dividerColor.withValues(alpha: 0.3),
                      ),
                      Expanded(
                        child: CupertinoPicker(
                          scrollController: FixedExtentScrollController(
                            initialItem: (current - 1).clamp(0, 59),
                          ),
                          itemExtent: 40,
                          onSelectedItemChanged: (index) {
                            setState(() => selected = index + 1);
                          },
                          children: List.generate(
                            60,
                            (index) => Center(
                              child: Text(
                                '${index + 1}秒',
                                style: theme.textTheme.titleMedium,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
          ),
    );
  }

  void _showSpeedPicker(
    BuildContext context,
    WidgetRef ref, {
    required String title,
    required double current,
    required ValueChanged<double> onSelected,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.6,
      ),
      builder:
          (context) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Divider(
                  height: 1,
                  color: theme.dividerColor.withValues(alpha: 0.3),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children:
                          _speedOptions
                              .map(
                                (speed) => _buildSpeedOption(
                                  context,
                                  ref,
                                  theme,
                                  speed,
                                  current,
                                  onSelected,
                                ),
                              )
                              .toList(),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
    );
  }

  void _showEnginePreferencePicker(
    BuildContext context,
    WidgetRef ref,
    EnginePreference current,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder:
          (context) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    '内核偏好',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Divider(
                  height: 1,
                  color: theme.dividerColor.withValues(alpha: 0.3),
                ),
                for (final preference in EnginePreference.values)
                  _buildEnginePreferenceOption(
                    context,
                    ref,
                    theme,
                    preference,
                    preference == current,
                  ),
                const SizedBox(height: 8),
              ],
            ),
          ),
    );
  }

  Widget _buildEnginePreferenceOption(
    BuildContext context,
    WidgetRef ref,
    ThemeData theme,
    EnginePreference preference,
    bool isSelected,
  ) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          ref
              .read(playbackSettingsProvider.notifier)
              .setEnginePreference(preference);
          Navigator.pop(context);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      preference.label,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight:
                            isSelected ? FontWeight.w500 : FontWeight.normal,
                        color: isSelected ? theme.colorScheme.primary : null,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _enginePreferenceDescriptions[preference]!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (isSelected) ...[
                const SizedBox(width: 12),
                Icon(
                  CupertinoIcons.checkmark,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSpeedOption(
    BuildContext context,
    WidgetRef ref,
    ThemeData theme,
    double speed,
    double current,
    ValueChanged<double> onSelected,
  ) {
    final isSelected = (speed - current).abs() < 0.001;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          onSelected(speed);
          Navigator.pop(context);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${speed}x',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight:
                        isSelected ? FontWeight.w500 : FontWeight.normal,
                    color: isSelected ? theme.colorScheme.primary : null,
                  ),
                ),
              ),
              if (isSelected)
                Icon(
                  CupertinoIcons.checkmark,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 播放缓存：上限与已用空间，点击已用空间进入缓存明细
class _PlaybackCacheSection extends ConsumerStatefulWidget {
  const _PlaybackCacheSection();

  @override
  ConsumerState<_PlaybackCacheSection> createState() =>
      _PlaybackCacheSectionState();
}

class _PlaybackCacheSectionState extends ConsumerState<_PlaybackCacheSection> {
  late Future<int> _usage = _loadUsage();

  Future<int> _loadUsage() =>
      ref.read(playbackCacheCatalogProvider).usedBytes();

  void _reload() {
    setState(() {
      _usage = _loadUsage();
    });
  }

  static String _quotaLabel(int gb) => gb == 0 ? '关闭' : '$gb GB';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final quotaGb = ref.watch(
      playbackSettingsProvider.select((s) => s.cacheQuotaGb),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        PlaybackSettingsScreen._buildSectionHeader('播放缓存', theme),
        PlaybackSettingsScreen._buildSettingsCard(
          isDark,
          children: [
            PlaybackSettingsScreen._buildListTile(
              context,
              theme,
              isDark,
              icon: CupertinoIcons.archivebox,
              iconColor: Colors.indigo,
              title: '缓存上限',
              subtitle: _quotaLabel(quotaGb),
              onTap: () => _showQuotaPicker(quotaGb),
            ),
            Divider(
              height: 1,
              indent: 60,
              color: theme.dividerColor.withValues(alpha: 0.3),
            ),
            FutureBuilder<int>(
              future: _usage,
              builder:
                  (context, snapshot) => PlaybackSettingsScreen._buildListTile(
                    context,
                    theme,
                    isDark,
                    icon: CupertinoIcons.tray_full,
                    iconColor: Colors.green,
                    title: '已缓存',
                    subtitle:
                        snapshot.hasError
                            ? '读取失败'
                            : snapshot.hasData
                            ? StorageManagementService.instance.formatSize(
                              snapshot.data!,
                            )
                            : '计算中…',
                    onTap: () async {
                      await context.push('/video-cache-detail');
                      if (mounted) _reload();
                    },
                  ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
          child: Text(
            '播放过的视频会在本机保留开头和上次播放位置附近的内容，再次打开时可以更快开始播放。'
            '超出上限时先清理最久没看的视频，已下载的视频不受影响',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  void _showQuotaPicker(int current) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder:
          (sheetContext) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    '缓存上限',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Divider(
                  height: 1,
                  color: theme.dividerColor.withValues(alpha: 0.3),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        for (final gb in PlaybackCacheConfig.quotaOptionsGb)
                          _buildQuotaOption(
                            sheetContext,
                            theme,
                            gb,
                            gb == current,
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
    );
  }

  Widget _buildQuotaOption(
    BuildContext sheetContext,
    ThemeData theme,
    int gb,
    bool isSelected,
  ) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () async {
          Navigator.pop(sheetContext);
          await ref.read(playbackSettingsProvider.notifier).setCacheQuotaGb(gb);
          if (mounted) _reload();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _quotaLabel(gb),
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight:
                            isSelected ? FontWeight.w500 : FontWeight.normal,
                        color: isSelected ? theme.colorScheme.primary : null,
                      ),
                    ),
                    if (gb == 0) ...[
                      const SizedBox(height: 4),
                      Text(
                        '播放时直接连接服务器，并清除已有的播放缓存',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (isSelected) ...[
                const SizedBox(width: 12),
                Icon(
                  CupertinoIcons.checkmark,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
