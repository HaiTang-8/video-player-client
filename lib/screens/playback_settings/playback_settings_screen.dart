import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/widgets/app_back_button.dart';
import '../../core/widgets/desktop_title_bar.dart';
import '../../core/window/window_controls.dart';
import '../../providers/providers.dart';

class PlaybackSettingsScreen extends ConsumerWidget {
  const PlaybackSettingsScreen({super.key});

  static const _speedOptions = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDesktop = WindowControls.isDesktop;
    final isDark = theme.brightness == Brightness.dark;
    final settings = ref.watch(playbackSettingsProvider);

    return Scaffold(
      appBar: isDesktop
          ? DesktopTitleBar(
              leading: AppBackButton(onPressed: () => context.pop()),
              title: const Text('播放设置'),
              centerTitle: false,
            )
          : AppBar(
              centerTitle: false,
              automaticallyImplyLeading: false,
              leadingWidth: kAppBackButtonWidth,
              titleSpacing: 1,
              leading: AppBackButton(onPressed: () => context.pop()),
              title: const Text('播放设置'),
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
                onTap: () => _showSeekDurationPicker(context, ref, settings.seekDuration),
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
                onTap: () => _showSpeedPicker(context, ref, settings.playbackSpeed),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
            child: Text(
              '设置视频播放的默认速度',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
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

  Widget _buildListTile(
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

  void _showSeekDurationPicker(BuildContext context, WidgetRef ref, int current) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    int selected = current;

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => SizedBox(
          height: 300,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    CupertinoButton(
                      child: Text(
                        '取消',
                        style: TextStyle(color: theme.colorScheme.primary),
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Text(
                      '快进/快退时长',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    CupertinoButton(
                      child: Text(
                        '完成',
                        style: TextStyle(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      onPressed: () {
                        ref.read(playbackSettingsProvider.notifier).setSeekDuration(selected);
                        Navigator.pop(context);
                      },
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: theme.dividerColor.withValues(alpha: 0.3)),
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

  void _showSpeedPicker(BuildContext context, WidgetRef ref, double current) {
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
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                '播放速度',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Divider(height: 1, color: theme.dividerColor.withValues(alpha: 0.3)),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: _speedOptions.map((speed) => _buildSpeedOption(
                        context,
                        ref,
                        theme,
                        speed,
                        current,
                      )).toList(),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
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
  ) {
    final isSelected = (speed - current).abs() < 0.001;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          ref.read(playbackSettingsProvider.notifier).setPlaybackSpeed(speed);
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
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
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
