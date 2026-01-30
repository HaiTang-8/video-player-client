import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/widgets/dialog_utils.dart';
import '../../providers/providers.dart';

class BlacklistManagerDialog extends ConsumerStatefulWidget {
  final int storageId;

  const BlacklistManagerDialog({super.key, required this.storageId});

  @override
  ConsumerState<BlacklistManagerDialog> createState() => _BlacklistManagerDialogState();
}

class _BlacklistManagerDialogState extends ConsumerState<BlacklistManagerDialog> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      loadBlacklist(ref, widget.storageId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final browseState = ref.watch(browseProvider(widget.storageId));
    final blacklist = browseState.blacklist.toList()..sort();

    return AlertDialog(
      title: Row(
        children: [
          Icon(CupertinoIcons.nosign, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          const Text('扫描黑名单'),
        ],
      ),
      content: SizedBox(
        width: 400,
        height: 300,
        child: blacklist.isEmpty
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      CupertinoIcons.folder_badge_minus,
                      size: 48,
                      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '暂无黑名单目录',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '长按目录可添加到黑名单',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              )
            : ListView.separated(
                itemCount: blacklist.length,
                separatorBuilder: (context, index) => Divider(
                  height: 1,
                  color: theme.dividerColor.withValues(alpha: 0.3),
                ),
                itemBuilder: (context, index) {
                  final path = blacklist[index];
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    leading: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        CupertinoIcons.folder,
                        size: 20,
                        color: Colors.orange,
                      ),
                    ),
                    title: Text(
                      path,
                      style: theme.textTheme.bodyMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: IconButton(
                      icon: Icon(
                        CupertinoIcons.xmark_circle_fill,
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                      ),
                      onPressed: () => _removeFromBlacklist(path),
                    ),
                  );
                },
              ),
      ),
      actions: [
        if (blacklist.isNotEmpty)
          TextButton(
            onPressed: _clearAll,
            child: Text(
              '清空全部',
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
        TextButton(
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认清空'),
        content: const Text('确定要清空所有黑名单目录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final success = await clearBlacklist(ref, widget.storageId);
      if (mounted) {
        DialogUtils.showToast(
          context: context,
          message: success ? '已清空黑名单' : '清空失败',
        );
      }
    }
  }
}
