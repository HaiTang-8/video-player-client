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
      ),
      body: state.tasks.isEmpty
          ? _buildEmptyState()
          : _buildContent(context, ref, state),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(CupertinoIcons.arrow_down_circle, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            '暂无下载任务',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context, WidgetRef ref, DownloadManagerState state) {
    // 检查是否所有任务都已暂停
    final allPaused = state.downloadingTasks.isNotEmpty &&
        state.downloadingTasks.every((t) => t.isPaused);

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        // 正在下载 Section
        if (state.downloadingTasks.isNotEmpty) ...[
          _DownloadSection(
            title: allPaused ? '已暂停' : '下载中',
            count: state.downloadingTasks.length,
            actions: [
              _SectionAction(
                icon: CupertinoIcons.xmark,
                label: '全部取消',
                onTap: () => _confirmCancelAll(context, ref),
              ),
              if (allPaused)
                _SectionAction(
                  icon: CupertinoIcons.play_fill,
                  label: '全部继续',
                  onTap: () => _resumeAll(ref, state.downloadingTasks),
                )
              else
                _SectionAction(
                  icon: CupertinoIcons.pause,
                  label: '全部暂停',
                  onTap: () => _pauseAll(ref, state.downloadingTasks),
                ),
            ],
            hint: '下载速度取决于文件源平台的限速策略',
            children: state.downloadingTasks
                .map((task) => _DownloadingItem(
                      task: task,
                      onPause: () => ref.read(downloadManagerProvider.notifier).pauseDownload(task.id),
                      onResume: () => ref.read(downloadManagerProvider.notifier).resumeDownload(task.id),
                      onCancel: () => _confirmDelete(context, ref, task),
                    ))
                .toList(),
          ),
        ],

        // 已完成 Section
        if (state.completedTasks.isNotEmpty) ...[
          _DownloadSection(
            title: '已完成',
            count: state.completedTasks.length,
            actions: [
              _SectionAction(
                icon: CupertinoIcons.trash,
                label: '全部删除',
                isDestructive: true,
                onTap: () => _confirmClearCompleted(context, ref),
              ),
            ],
            children: state.completedTasks
                .map((task) => _CompletedItem(
                      task: task,
                      onDelete: () => _confirmDelete(context, ref, task),
                    ))
                .toList(),
          ),
        ],

        // 失败 Section
        if (state.failedTasks.isNotEmpty) ...[
          _DownloadSection(
            title: '失败',
            count: state.failedTasks.length,
            actions: [
              _SectionAction(
                icon: CupertinoIcons.arrow_clockwise,
                label: '全部重试',
                onTap: () => _retryAll(ref, state.failedTasks),
              ),
            ],
            children: state.failedTasks
                .map((task) => _FailedItem(
                      task: task,
                      onRetry: () => ref.read(downloadManagerProvider.notifier).retryDownload(task.id),
                      onDelete: () => ref.read(downloadManagerProvider.notifier).deleteDownload(task.id),
                    ))
                .toList(),
          ),
        ],

        const SizedBox(height: 32),
      ],
    );
  }

  void _pauseAll(WidgetRef ref, List<DownloadTask> tasks) {
    for (final task in tasks) {
      if (task.isDownloading || task.isPending) {
        ref.read(downloadManagerProvider.notifier).pauseDownload(task.id);
      }
    }
  }

  void _resumeAll(WidgetRef ref, List<DownloadTask> tasks) {
    for (final task in tasks) {
      if (task.isPaused) {
        ref.read(downloadManagerProvider.notifier).resumeDownload(task.id);
      }
    }
  }

  void _retryAll(WidgetRef ref, List<DownloadTask> tasks) {
    for (final task in tasks) {
      ref.read(downloadManagerProvider.notifier).retryDownload(task.id);
    }
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, DownloadTask task) {
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('删除下载'),
        content: Text('确定要删除「${task.fileName ?? task.episodeName}」吗？'),
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

  void _confirmCancelAll(BuildContext context, WidgetRef ref) {
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('取消全部下载'),
        content: const Text('确定要取消所有正在下载的任务吗？'),
        actions: [
          CupertinoDialogAction(
            child: const Text('取消'),
            onPressed: () => Navigator.pop(ctx),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            child: const Text('确定'),
            onPressed: () {
              Navigator.pop(ctx);
              final state = ref.read(downloadManagerProvider);
              for (final task in state.downloadingTasks) {
                ref.read(downloadManagerProvider.notifier).deleteDownload(task.id);
              }
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
        title: const Text('删除全部已完成'),
        content: const Text('确定要删除所有已完成的下载吗？\n文件也会被删除。'),
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
              ref.read(downloadManagerProvider.notifier).deleteAllCompleted();
            },
          ),
        ],
      ),
    );
  }
}

class _SectionAction {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDestructive;

  _SectionAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isDestructive = false,
  });
}

class _DownloadSection extends StatelessWidget {
  final String title;
  final int count;
  final List<_SectionAction> actions;
  final String? hint;
  final List<Widget> children;

  const _DownloadSection({
    required this.title,
    required this.count,
    this.actions = const [],
    this.hint,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        // Header
        Row(
          children: [
            Text(
              '$title ($count)',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.black,
              ),
            ),
            const Spacer(),
            ...actions.map((action) => Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: GestureDetector(
                    onTap: action.onTap,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          action.icon,
                          size: 14,
                          color: action.isDestructive
                              ? CupertinoColors.systemRed
                              : CupertinoColors.systemBlue,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          action.label,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: action.isDestructive
                                ? CupertinoColors.systemRed
                                : CupertinoColors.systemBlue,
                          ),
                        ),
                      ],
                    ),
                  ),
                )),
          ],
        ),
        // Hint
        if (hint != null) ...[
          const SizedBox(height: 4),
          Text(
            hint!,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
          ),
        ],
        const SizedBox(height: 12),
        // Items
        Container(
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
}

class _DownloadingItem extends StatelessWidget {
  final DownloadTask task;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onCancel;

  const _DownloadingItem({
    required this.task,
    required this.onPause,
    required this.onResume,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final isPaused = task.isPaused;
    final downloadedMB = task.downloadedBytes / (1024 * 1024);
    final totalMB = (task.fileSize ?? 0) / (1024 * 1024);
    final totalGB = totalMB / 1024;

    String sizeText;
    if (totalGB >= 1) {
      sizeText = '${downloadedMB.toStringAsFixed(2)} MB / ${totalGB.toStringAsFixed(2)} GB';
    } else {
      sizeText = '${downloadedMB.toStringAsFixed(2)} MB / ${totalMB.toStringAsFixed(2)} MB';
    }

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          // 视频图标
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: CupertinoColors.systemBlue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              CupertinoIcons.play_rectangle_fill,
              color: CupertinoColors.systemBlue,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          // 内容
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.fileName ?? '${task.tvShowName}.S${task.seasonNumber.toString().padLeft(2, '0')}E${task.episodeNumber.toString().padLeft(2, '0')}.mp4',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: Colors.black,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      sizeText,
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                    ),
                    const Spacer(),
                    if (task.isDownloading)
                      Text(
                        task.formattedSpeed,
                        style: const TextStyle(
                          fontSize: 13,
                          color: CupertinoColors.systemBlue,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: task.progress,
                    minHeight: 3,
                    backgroundColor: Colors.grey.shade300,
                    valueColor: const AlwaysStoppedAnimation(CupertinoColors.systemBlue),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // 暂停/继续按钮
          GestureDetector(
            onTap: isPaused ? onResume : onPause,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Icon(
                isPaused ? CupertinoIcons.play_fill : CupertinoIcons.pause_fill,
                size: 14,
                color: Colors.grey.shade600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // 删除按钮
          GestureDetector(
            onTap: onCancel,
            child: Icon(
              CupertinoIcons.xmark_circle_fill,
              size: 24,
              color: Colors.grey.shade400,
            ),
          ),
        ],
      ),
    );
  }
}

class _CompletedItem extends StatelessWidget {
  final DownloadTask task;
  final VoidCallback onDelete;

  const _CompletedItem({
    required this.task,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          // 视频图标
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: CupertinoColors.systemGreen.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              CupertinoIcons.play_rectangle_fill,
              color: CupertinoColors.systemGreen,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          // 内容
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.fileName ?? task.displayTitle,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: Colors.black,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  task.formattedFileSize,
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // 删除按钮
          GestureDetector(
            onTap: onDelete,
            child: Icon(
              CupertinoIcons.trash,
              size: 20,
              color: Colors.grey.shade400,
            ),
          ),
        ],
      ),
    );
  }
}

class _FailedItem extends StatelessWidget {
  final DownloadTask task;
  final VoidCallback onRetry;
  final VoidCallback onDelete;

  const _FailedItem({
    required this.task,
    required this.onRetry,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          // 视频图标
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: CupertinoColors.systemRed.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              CupertinoIcons.exclamationmark_triangle_fill,
              color: CupertinoColors.systemRed,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          // 内容
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.fileName ?? task.displayTitle,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: Colors.black,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  task.errorMessage ?? '下载失败',
                  style: const TextStyle(fontSize: 13, color: CupertinoColors.systemRed),
                  maxLines: 3,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // 重试按钮
          GestureDetector(
            onTap: onRetry,
            child: Icon(
              CupertinoIcons.arrow_clockwise,
              size: 20,
              color: CupertinoColors.systemBlue,
            ),
          ),
          const SizedBox(width: 16),
          // 删除按钮
          GestureDetector(
            onTap: onDelete,
            child: Icon(
              CupertinoIcons.trash,
              size: 20,
              color: Colors.grey.shade400,
            ),
          ),
        ],
      ),
    );
  }
}
