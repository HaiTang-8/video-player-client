import '../../data/models/download_task.dart';

/// Returns the next pending tasks to start, respecting the global concurrency limit.
///
/// This is pure logic (no side effects) so it can be unit-tested.
List<DownloadTask> pickPendingTasksToStart(
  List<DownloadTask> tasks, {
  required int maxConcurrent,
}) {
  final downloadingCount = tasks.where((t) => t.status == DownloadStatus.downloading).length;
  final availableSlots = maxConcurrent - downloadingCount;
  if (availableSlots <= 0) return const [];

  return tasks
      .where((t) => t.status == DownloadStatus.pending)
      .take(availableSlots)
      .toList(growable: false);
}

