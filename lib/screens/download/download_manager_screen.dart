import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/app_back_button.dart';
import '../../data/models/download_task.dart';
import '../../providers/download_provider.dart';

class DownloadManagerScreen extends ConsumerWidget {
  const DownloadManagerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(downloadManagerProvider);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: false,
        leadingWidth: kAppBackButtonWidth,
        leading: AppBackButton(
          onPressed: () => context.pop(),
          color: Colors.black,
        ),
        title: const Text(
          '下载管理',
          style: TextStyle(color: Colors.black, fontSize: 17),
        ),
        actions: [
          if (state.completedTasks.isNotEmpty)
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                '清空已完成',
                style: TextStyle(color: Colors.red.shade400, fontSize: 14),
              ),
              onPressed: () => _confirmClearCompleted(context, ref),
            ),
        ],
      ),
      body: state.tasks.isEmpty
          ? _buildEmptyState()
          : _buildTaskList(context, ref, state),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.download_done, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            '暂无下载任务',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskList(BuildContext context, WidgetRef ref, DownloadManagerState state) {
    final sections = <_TaskSection>[];

    if (state.downloadingTasks.isNotEmpty) {
      sections.add(_TaskSection(title: '下载中', tasks: state.downloadingTasks));
    }
    if (state.completedTasks.isNotEmpty) {
      sections.add(_TaskSection(title: '已完成', tasks: state.completedTasks));
    }
    if (state.failedTasks.isNotEmpty) {
      sections.add(_TaskSection(title: '失败', tasks: state.failedTasks));
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: sections.length,
      itemBuilder: (context, index) {
        final section = sections[index];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                '${section.title} (${section.tasks.length})',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey.shade600,
                ),
              ),
            ),
            ...section.tasks.map((task) => _DownloadTaskItem(
              task: task,
              onPause: () => ref.read(downloadManagerProvider.notifier).pauseDownload(task.id),
              onResume: () => ref.read(downloadManagerProvider.notifier).resumeDownload(task.id),
              onRetry: () => ref.read(downloadManagerProvider.notifier).retryDownload(task.id),
              onDelete: () => _confirmDelete(context, ref, task),
            )),
            if (index < sections.length - 1) const SizedBox(height: 16),
          ],
        );
      },
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, DownloadTask task) {
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('删除下载'),
        content: Text('确定要删除「${task.episodeName}」吗？\n${task.isCompleted ? '已下载的文件也会被删除。' : ''}'),
        actions: [
          CupertinoDialogAction(
            child: const Text('取消'),
            onPressed: () => Navigator.pop(ctx),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            child: const Text('删除'),
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(downloadManagerProvider.notifier).deleteDownload(task.id);
            },
          ),
        ],
      ),
    );
  }

  void _confirmClearCompleted(BuildContext context, WidgetRef ref) {
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('清空已完成'),
        content: const Text('确定要删除所有已完成的下载吗？\n文件也会被删除。'),
        actions: [
          CupertinoDialogAction(
            child: const Text('取消'),
            onPressed: () => Navigator.pop(ctx),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            child: const Text('清空'),
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(downloadManagerProvider.notifier).deleteAllCompleted();
            },
          ),
        ],
      ),
    );
  }
}

class _TaskSection {
  final String title;
  final List<DownloadTask> tasks;

  _TaskSection({required this.title, required this.tasks});
}

class _DownloadTaskItem extends StatelessWidget {
  final DownloadTask task;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onRetry;
  final VoidCallback onDelete;

  const _DownloadTaskItem({
    required this.task,
    required this.onPause,
    required this.onResume,
    required this.onRetry,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.tvShowName,
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      task.displayTitle,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: Colors.black,
                      ),
                    ),
                  ],
                ),
              ),
              _buildActionButton(),
            ],
          ),
          if (task.isDownloading) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: task.progress,
              backgroundColor: Colors.grey.shade200,
              valueColor: const AlwaysStoppedAnimation(Color(0xFF4CAF50)),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  task.formattedProgress,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
                Text(
                  '${(task.progress * 100).toInt()}%',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
          ],
          if (task.isFailed && task.errorMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              task.errorMessage!,
              style: TextStyle(fontSize: 12, color: Colors.red.shade400),
            ),
          ],
          if (task.isCompleted) ...[
            const SizedBox(height: 4),
            Text(
              task.formattedFileSize,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActionButton() {
    if (task.isDownloading) {
      return GestureDetector(
        onTap: onPause,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.grey.shade200,
          ),
          child: const Icon(Icons.pause, size: 18, color: Colors.black54),
        ),
      );
    }

    if (task.isPaused || task.isPending) {
      return GestureDetector(
        onTap: onResume,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.blue.shade50,
          ),
          child: Icon(Icons.play_arrow, size: 18, color: Colors.blue.shade600),
        ),
      );
    }

    if (task.isFailed) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: onRetry,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.orange.shade50,
              ),
              child: Icon(Icons.refresh, size: 18, color: Colors.orange.shade600),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onDelete,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.red.shade50,
              ),
              child: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade400),
            ),
          ),
        ],
      );
    }

    if (task.isCompleted) {
      return GestureDetector(
        onTap: onDelete,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.red.shade50,
          ),
          child: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade400),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}
