import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/widgets/app_back_button.dart';
import '../../core/widgets/desktop_title_bar.dart';
import '../../core/widgets/loading_widget.dart';
import '../../core/window/window_controls.dart';
import '../../data/models/models.dart';
import '../../data/services/api_client.dart';
import '../../providers/providers.dart';

/// AI 整理预览页：展示服务端生成的整理方案，并在二次确认后应用。
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
  ConsumerState<AiTidyPreviewScreen> createState() =>
      _AiTidyPreviewScreenState();
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

    return Scaffold(
      appBar:
          isDesktop
              ? DesktopTitleBar(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                // 与影视详情页保持一致：标题靠左，不居中
                centerTitle: false,
                leading: AppBackButton(
                  onPressed: () => Navigator.pop(context, false),
                  color: Colors.black,
                ),
                title: const Text('AI 整理预览'),
              )
              : AppBar(
                backgroundColor: Colors.white,
                elevation: 0,
                toolbarHeight: 44,
                // 与影视详情页保持一致：返回按钮用“<”样式，标题靠左（避免 iOS 默认居中）
                centerTitle: false,
                automaticallyImplyLeading: false,
                leadingWidth: kAppBackButtonWidth,
                titleSpacing: 1,
                leading: AppBackButton(
                  onPressed: () => Navigator.pop(context, false),
                  color: Colors.black,
                ),
                title: const Text(
                  'AI 整理预览',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
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
              const Divider(height: 1),
              Expanded(child: _buildOperations(context, plan)),
              const Divider(height: 1),
              _buildFooter(context, plan),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeader(BuildContext context, AiTidyPlan plan) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            plan.summary,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text('目录：${plan.rootPath}'),
          const SizedBox(height: 4),
          Text('文件数：${plan.fileCount}  ·  变更数：${plan.operations.length}'),
          const SizedBox(height: 4),
          Text(
            'Provider：${plan.provider}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          if (plan.warnings.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '注意事项',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.error,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...plan.warnings.take(3).map((w) => Text('• $w')),
                  if (plan.warnings.length > 3)
                    Text('… 还有 ${plan.warnings.length - 3} 条'),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOperations(BuildContext context, AiTidyPlan plan) {
    if (plan.operations.isEmpty) {
      return const EmptyWidget(
        message: '没有需要变更的文件\n（或 AI 未生成有效建议）',
        icon: Icons.rule_folder_outlined,
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: plan.operations.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final op = plan.operations[index];
        return ListTile(
          leading: const Icon(Icons.drive_file_move_outline),
          title: Text(op.to),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('来自：${op.from}'),
              if (op.reason != null && op.reason!.trim().isNotEmpty)
                Text('原因：${op.reason}'),
            ],
          ),
          onLongPress: () {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('长按复制功能可在浏览页使用')));
          },
        );
      },
    );
  }

  Widget _buildFooter(BuildContext context, AiTidyPlan plan) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed:
                    _isApplying ? null : () => Navigator.pop(context, false),
                child: const Text('返回'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed:
                    _isApplying || plan.operations.isEmpty
                        ? null
                        : () => _confirmAndApply(context, plan),
                child:
                    _isApplying
                        ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                        : const Text('应用（需二次确认）'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmAndApply(BuildContext context, AiTidyPlan plan) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('二次确认'),
            content: Text(
              '将应用 ${plan.operations.length} 条变更，修改目录：\n${plan.rootPath}\n\n此操作会移动/重命名文件，可能耗时。\n确认继续吗？',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('我已确认，继续'),
              ),
            ],
          ),
    );

    if (confirmed != true) return;

    final service = ref.read(storageServiceProvider);
    if (service == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('未连接服务器')));
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已应用 ${resp.data!.applied} 条变更')));
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(resp.error ?? '应用失败')));
    }
  }
}
