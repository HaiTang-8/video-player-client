import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/widgets/desktop_title_bar.dart';
import '../../core/widgets/server_connection_error_widget.dart';
import '../../core/window/window_controls.dart';
import '../../providers/providers.dart';

class ConnectionErrorScreen extends ConsumerStatefulWidget {
  const ConnectionErrorScreen({super.key});

  @override
  ConsumerState<ConnectionErrorScreen> createState() => _ConnectionErrorScreenState();
}

class _ConnectionErrorScreenState extends ConsumerState<ConnectionErrorScreen> {
  bool _isRetrying = false;

  Future<void> _handleRetry() async {
    setState(() => _isRetrying = true);

    final serverUrl = ref.read(serverUrlProvider);
    if (serverUrl != null && serverUrl.isNotEmpty) {
      final success = await ref.read(serverConnectionProvider.notifier).testConnection(serverUrl);
      if (success && mounted) {
        context.go('/library');
        return;
      }
    }

    if (mounted) {
      setState(() => _isRetrying = false);
    }
  }

  void _handleGoToSettings() {
    context.go('/config');
  }

  @override
  Widget build(BuildContext context) {
    final serverUrl = ref.watch(serverUrlProvider);
    final isDesktop = WindowControls.isDesktop;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final content = ServerConnectionErrorWidget(
      serverUrl: serverUrl,
      isRetrying: _isRetrying,
      onRetry: _handleRetry,
      onGoToSettings: _handleGoToSettings,
    );

    if (isDesktop) {
      return Scaffold(
        appBar: const DesktopTitleBar(
          title: Text('连接错误'),
          centerTitle: true,
        ),
        body: content,
      );
    }

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7),
      body: SafeArea(child: content),
    );
  }
}
