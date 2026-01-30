import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;
import '../../core/widgets/dialog_utils.dart';
import '../../providers/providers.dart';

class BlacklistManagerDialog extends ConsumerStatefulWidget {
  final int storageId;

  const BlacklistManagerDialog({super.key, required this.storageId});

  @override
  ConsumerState<BlacklistManagerDialog> createState() =>
      _BlacklistManagerDialogState();
}

class _BlacklistManagerDialogState
    extends ConsumerState<BlacklistManagerDialog> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      loadBlacklist(ref, widget.storageId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = shadcn.Theme.of(context);
    final browseState = ref.watch(browseProvider(widget.storageId));
    final blacklist = browseState.blacklist.toList()..sort();
    // shadcn_flutter 的 destructive 默认背景在某些状态（hover/focus 等）会使用较低 alpha，
    // 在弹窗里看起来像“灰白遮罩”。统一状态色，避免视觉发灰。
    final destructiveStyle = shadcn.ButtonVariance.destructive
        .withBackgroundColor(
          color: theme.colorScheme.destructive,
          hoverColor: theme.colorScheme.destructive,
          focusColor: theme.colorScheme.destructive,
        );

    return shadcn.AlertDialog(
      title: Row(
        children: [
          Icon(
            shadcn.LucideIcons.ban,
            color: theme.colorScheme.primary,
            size: 20,
          ),
          const SizedBox(width: 8),
          const Text('扫描黑名单'),
        ],
      ),
      content:
          blacklist.isEmpty
              ? SizedBox(
                height: 300,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        shadcn.LucideIcons.folderMinus,
                        size: 48,
                        color: theme.colorScheme.mutedForeground.withValues(
                          alpha: 0.5,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '暂无黑名单目录',
                        style: theme.typography.base.copyWith(
                          color: theme.colorScheme.mutedForeground,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '长按目录可添加到黑名单',
                        style: theme.typography.small.copyWith(
                          color: theme.colorScheme.mutedForeground.withValues(
                            alpha: 0.7,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              )
              : SizedBox(
                height: 300,
                // 这里用 LayoutBuilder + ConstrainedBox 强制列表内容“撑满”弹窗可用宽度；
                // 否则在某些桌面端/自定义 Dialog 实现里，滚动容器会让子节点按内容宽度收缩，
                // 看起来像是右侧留了一大块空白（item 没有按弹窗宽度占满）。
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final minWidth =
                        constraints.maxWidth.isFinite
                            ? constraints.maxWidth
                            : 0.0;
                    return SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minWidth: minWidth),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children:
                              blacklist.asMap().entries.map((entry) {
                                final index = entry.key;
                                final path = entry.value;
                                return Column(
                                  children: [
                                    if (index > 0)
                                      Divider(
                                        height: 1,
                                        color: theme.colorScheme.border
                                            .withValues(alpha: 0.3),
                                      ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 8,
                                        horizontal: 4,
                                      ),
                                      child: SizedBox(
                                        width: double.infinity,
                                        child: Row(
                                          children: [
                                            Container(
                                              width: 36,
                                              height: 36,
                                              decoration: BoxDecoration(
                                                color: Colors.orange.withValues(
                                                  alpha: 0.15,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: const Icon(
                                                shadcn.LucideIcons.folder,
                                                size: 20,
                                                color: Colors.orange,
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Text(
                                                path,
                                                style: theme.typography.small,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            shadcn.GhostButton(
                                              size: shadcn.ButtonSize.small,
                                              density:
                                                  shadcn.ButtonDensity.icon,
                                              onPressed:
                                                  () => _removeFromBlacklist(
                                                    path,
                                                  ),
                                              child: Icon(
                                                shadcn.LucideIcons.x,
                                                size: 16,
                                                color:
                                                    theme
                                                        .colorScheme
                                                        .mutedForeground,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              }).toList(),
                        ),
                      ),
                    );
                  },
                ),
              ),
      actions: [
        if (blacklist.isNotEmpty)
          shadcn.Button.destructive(
            style: destructiveStyle,
            disableFocusOutline: true,
            onPressed: _clearAll,
            child: const Text('清空全部'),
          ),
        shadcn.OutlineButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }

  Future<void> _removeFromBlacklist(String path) async {
    final success = await removeFromBlacklist(ref, widget.storageId, path);
    if (mounted && success) {
      DialogUtils.showToast(context: context, message: '已从黑名单移除');
    }
  }

  Future<void> _clearAll() async {
    final confirmed = await DialogUtils.showConfirmDialog(
      context: context,
      title: '确认清空',
      content: '确定要清空所有黑名单目录吗？',
      isDestructive: true,
      confirmText: '清空',
    );

    if (confirmed == true && mounted) {
      final success = await clearBlacklist(ref, widget.storageId);
      if (mounted) {
        DialogUtils.showToast(
          context: context,
          message: success ? '已清空黑名单' : '清空失败',
          isError: !success,
        );
      }
    }
  }
}
