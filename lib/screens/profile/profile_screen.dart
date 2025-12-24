import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/widgets/desktop_title_bar.dart';
import '../../core/window/window_controls.dart';
import '../../providers/providers.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDesktop = WindowControls.isDesktop;
    final isDark = theme.brightness == Brightness.dark;
    final playbackSettings = ref.watch(playbackSettingsProvider);

    return Scaffold(
      backgroundColor: isDark ? null : const Color(0xFFF2F2F7),
      appBar: isDesktop
          ? const DesktopTitleBar(
              title: Text('我的'),
              centerTitle: true,
            )
          : AppBar(
              title: const Text('我的'),
            ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          _buildSectionHeader('播放', theme),
          _buildSettingsCard(
            context,
            theme,
            isDark,
            children: [
              _buildListTile(
                context,
                icon: CupertinoIcons.forward_end,
                iconColor: Colors.orange,
                title: '快进/快退时长',
                subtitle: '${playbackSettings.seekDuration}秒',
                onTap: () => context.push('/playback-settings'),
              ),
              _buildDivider(theme),
              _buildListTile(
                context,
                icon: CupertinoIcons.speedometer,
                iconColor: Colors.blue,
                title: '播放速度',
                subtitle: '${playbackSettings.playbackSpeed}x',
                onTap: () => context.push('/playback-settings'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildSectionHeader('通用', theme),
          _buildSettingsCard(
            context,
            theme,
            isDark,
            children: [
              _buildListTile(
                context,
                icon: CupertinoIcons.settings,
                iconColor: Colors.grey,
                title: '设置',
                onTap: () => context.push('/settings'),
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

  Widget _buildSettingsCard(
    BuildContext context,
    ThemeData theme,
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

  Widget _buildListTile(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

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

  Widget _buildDivider(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(left: 60),
      child: Divider(
        height: 1,
        thickness: 0.5,
        color: theme.dividerColor.withValues(alpha: 0.3),
      ),
    );
  }
}
