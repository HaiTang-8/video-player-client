import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/core/utils/download_queue.dart';
import 'package:media_player/data/models/download_task.dart';

DownloadTask _task(String id, DownloadStatus status) {
  return DownloadTask(
    id: id,
    type: DownloadType.episode,
    downloadUrl: '',
    localPath: '/tmp/$id',
    status: status,
    createdAt: DateTime(2024, 1, 1),
  );
}

void main() {
  group('pickPendingTasksToStart', () {
    test('returns empty when no slots are available', () {
      final tasks = [
        _task('a', DownloadStatus.downloading),
        _task('b', DownloadStatus.downloading),
        _task('c', DownloadStatus.pending),
      ];

      expect(pickPendingTasksToStart(tasks, maxConcurrent: 2), isEmpty);
    });

    test('returns pending tasks up to available slots (stable order)', () {
      final tasks = [
        _task('a', DownloadStatus.downloading),
        _task('b', DownloadStatus.pending),
        _task('c', DownloadStatus.pending),
        _task('d', DownloadStatus.pending),
      ];

      final picked = pickPendingTasksToStart(tasks, maxConcurrent: 2);
      expect(picked.map((t) => t.id).toList(), ['b']);
    });

    test('skips non-pending tasks', () {
      final tasks = [
        _task('a', DownloadStatus.failed),
        _task('b', DownloadStatus.pending),
        _task('c', DownloadStatus.completed),
        _task('d', DownloadStatus.pending),
      ];

      final picked = pickPendingTasksToStart(tasks, maxConcurrent: 3);
      expect(picked.map((t) => t.id).toList(), ['b', 'd']);
    });
  });
}

