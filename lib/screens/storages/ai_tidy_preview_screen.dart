import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/widgets/app_back_button.dart';
import '../../core/widgets/desktop_title_bar.dart';
import '../../core/widgets/loading_widget.dart';
import '../../core/window/window_controls.dart';
import '../../data/models/models.dart';
import '../../data/services/api_client.dart';
import '../../providers/providers.dart';

class AiTidyPreviewScreen extends ConsumerStatefulWidget {
  final int storageId;
  final String rootPath;
  final int maxFiles;

  const AiTidyPreviewScreen({
    super.key,
    required this.storageId,
    required this.rootPath,
    required this.maxFiles,
  });

  @override
  ConsumerState<AiTidyPreviewScreen> createState() => _AiTidyPreviewScreenState();
}

class _AiTidyPreviewScreenState extends ConsumerState<AiTidyPreviewScreen> {
  late Future<ApiResponse<AiTidyPlan>> _future;
  bool _isApplying = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<ApiResponse<AiTidyPlan>> _load() async {
    final service = ref.read(storageServiceProvider);
    if (service == null) {
      return ApiResponse<AiTidyPlan>(success: false, error: '未连接服务器');
    }
    return service.aiTidyPreview(
      widget.storageId,
      path: widget.rootPath,
      maxFiles: widget.maxFiles,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = WindowControls.isDesktop;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: isDesktop
          ? DesktopTitleBar(
              centerTitle: false,
              leading: AppBackButton(
                onPressed: () => Navigator.pop(context, false),
              ),
              title: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(CupertinoIcons.wand_stars, size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  const Text('AI 整理预览'),
                ],
              ),
            )
          : AppBar(
              elevation: 0,
              toolbarHeight: 44,
              centerTitle: false,
              automaticallyImplyLeading: false,
              leadingWidth: kAppBackButtonWidth,
              titleSpacing: 1,
              leading: AppBackButton(
                onPressed: () => Navigator.pop(context, false),
              ),
              title: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(CupertinoIcons.wand_stars, size: 16, color: theme.colorScheme.primary),
                  const SizedBox(width: 6),
                  const Text('AI 整理预览'),
                ],
              ),
            ),
      body: FutureBuilder<ApiResponse<AiTidyPlan>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const LoadingWidget(message: '正在生成预览方案...');
          }

          final resp = snapshot.data;
          if (resp == null || !resp.isSuccess || resp.data == null) {
            return AppErrorWidget(
              message: resp?.error ?? '生成预览方案失败',
              onRetry: () {
                setState(() {
                  _future = _load();
                });
              },
            );
          }

          final plan = resp.data!;
          return Column(
            children: [
              _buildHeader(context, plan),
              Divider(height: 1, color: theme.dividerColor.withValues(alpha: 0.3)),
              Expanded(child: _buildOperations(context, plan)),
              Divider(height: 1, color: theme.dividerColor.withValues(alpha: 0.3)),
              _buildFooter(context, plan),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeader(BuildContext context, AiTidyPlan plan) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            plan.summary,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1C1C1E) : Colors.grey[100],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                _buildInfoRow(theme, CupertinoIcons.folder, '目录', plan.rootPath),
                const SizedBox(height: 8),
                _buildInfoRow(theme, CupertinoIcons.doc, '文件数', '${plan.fileCount}'),
                const SizedBox(height: 8),
                _buildInfoRow(theme, CupertinoIcons.arrow_right_arrow_left, '变更数', '${plan.operations.length}'),
              ],
            ),
          ),
          if (plan.warnings.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(CupertinoIcons.exclamationmark_triangle, size: 16, color: Colors.orange),
                      const SizedBox(width: 6),
                      Text(
                        '注意事项',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: Colors.orange,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...plan.warnings.take(3).map((w) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          '• $w',
                          style: theme.textTheme.bodySmall,
                        ),
                      )),
                  if (plan.warnings.length > 3)
                    Text(
                      '… 还有 ${plan.warnings.length - 3} 条',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoRow(ThemeData theme, IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Text(
          '$label：',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: theme.textTheme.bodyMedium,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildOperations(BuildContext context, AiTidyPlan plan) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (plan.operations.isEmpty) {
      return const EmptyWidget(
        message: '没有需要变更的文件\n（或 AI 未生成有效建议）',
        icon: CupertinoIcons.folder,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: 1,
      itemBuilder: (context, _) {
        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              for (int i = 0; i < plan.operations.length; i++) ...[
                _OperationTile(operation: plan.operations[i]),
                if (i < plan.operations.length - 1)
                  Padding(
                    padding: const EdgeInsets.only(left: 60),
                    child: Divider(
                      height: 1,
                      thickness: 0.5,
                      color: theme.dividerColor.withValues(alpha: 0.3),
                    ),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildFooter(BuildContext context, AiTidyPlan plan) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _isApplying ? null : () => Navigator.pop(context, false),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text('返回'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: _isApplying || plan.operations.isEmpty
                    ? null
                    : () => _confirmAndApply(context, plan),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: _isApplying
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('应用变更'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmAndApply(BuildContext context, AiTidyPlan plan) async {
    final theme = Theme.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(CupertinoIcons.exclamationmark_circle, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            const Text('确认应用'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('将应用 ${plan.operations.length} 条变更'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                plan.rootPath,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '此操作会移动/重命名文件，可能耗时。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认应用'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final service = ref.read(storageServiceProvider);
    if (service == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('未连接服务器')),
        );
      }
      return;
    }

    setState(() {
      _isApplying = true;
    });
    final resp = await service.aiTidyApply(
      widget.storageId,
      path: plan.rootPath,
      snapshotHash: plan.snapshotHash,
      operations: plan.operations,
    );
    setState(() {
      _isApplying = false;
    });

    if (!context.mounted) return;

    if (resp.isSuccess && resp.data != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已应用 ${resp.data!.applied} 条变更')),
      );
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(resp.error ?? '应用失败')),
      );
    }
  }
}

class _OperationTile extends StatelessWidget {
  final AiTidyOperation operation;

  const _OperationTile({required this.operation});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              CupertinoIcons.arrow_right_arrow_left,
              size: 18,
              color: Colors.green,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  operation.to,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  '来自：${operation.from}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (operation.reason != null && operation.reason!.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    '原因：${operation.reason}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
