import 'package:flutter/material.dart';
import '../../core/widgets/desktop_title_bar.dart';
import '../../core/window/window_controls.dart';

/// 我的页面 - 占位
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDesktop = WindowControls.isDesktop;

    return Scaffold(
      appBar: isDesktop
          ? const DesktopTitleBar(
              title: Text('我的'),
              centerTitle: true,
            )
          : AppBar(
              title: const Text('我的'),
            ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.construction_outlined,
              size: 80,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 24),
            Text(
              '功能开发中...',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '敬请期待',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.outline.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
