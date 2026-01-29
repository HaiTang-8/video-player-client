import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;

class ServerConnectionErrorWidget extends StatelessWidget {
  final VoidCallback? onRetry;
  final VoidCallback? onGoToSettings;
  final String? serverUrl;
  final bool isRetrying;

  const ServerConnectionErrorWidget({
    super.key,
    this.onRetry,
    this.onGoToSettings,
    this.serverUrl,
    this.isRetrying = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = shadcn.Theme.of(context);
    final isDark = theme.colorScheme.background.computeLuminance() < 0.5;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: theme.colorScheme.destructive.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  CupertinoIcons.wifi_slash,
                  size: 40,
                  color: theme.colorScheme.destructive,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                '无法连接到服务器',
                style: theme.typography.h3.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                '请检查网络连接或服务器地址是否正确',
                style: theme.typography.base.copyWith(
                  color: theme.colorScheme.mutedForeground,
                ),
                textAlign: TextAlign.center,
              ),
              if (serverUrl != null && serverUrl!.isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.black.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: theme.colorScheme.border,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        CupertinoIcons.link,
                        size: 16,
                        color: theme.colorScheme.mutedForeground,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          serverUrl!,
                          style: theme.typography.small.copyWith(
                            color: theme.colorScheme.mutedForeground,
                            fontFamily: 'monospace',
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 32),
              LayoutBuilder(
                builder: (context, constraints) {
                  final isNarrow = constraints.maxWidth < 300;
                  if (isNarrow) {
                    return Column(
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: _buildRetryButton(theme),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: _buildSettingsButton(theme),
                        ),
                      ],
                    );
                  }
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Expanded(child: _buildRetryButton(theme)),
                      const SizedBox(width: 12),
                      Expanded(child: _buildSettingsButton(theme)),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRetryButton(shadcn.ThemeData theme) {
    return shadcn.PrimaryButton(
      onPressed: isRetrying ? null : onRetry,
      child: isRetrying
          ? Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: shadcn.CircularProgressIndicator(
                    strokeWidth: 2,
                    color: theme.colorScheme.primaryForeground,
                  ),
                ),
                const SizedBox(width: 8),
                const Text('连接中...'),
              ],
            )
          : const Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(CupertinoIcons.arrow_clockwise, size: 16),
                SizedBox(width: 8),
                Text('重试连接'),
              ],
            ),
    );
  }

  Widget _buildSettingsButton(shadcn.ThemeData theme) {
    return shadcn.OutlineButton(
      onPressed: onGoToSettings,
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(CupertinoIcons.gear, size: 16),
          SizedBox(width: 8),
          Text('服务器设置'),
        ],
      ),
    );
  }
}
