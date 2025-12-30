import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/models.dart';
import '../data/services/database_backup_service.dart';
import 'server_provider.dart';

final databaseBackupServiceProvider = Provider<DatabaseBackupService?>((ref) {
  final client = ref.watch(apiClientProvider);
  if (client == null) return null;
  return DatabaseBackupService(client);
});

final databaseBackupsProvider = StateNotifierProvider<
  DatabaseBackupsNotifier,
  AsyncValue<List<DatabaseBackupInfo>>
>((ref) {
  final service = ref.watch(databaseBackupServiceProvider);
  return DatabaseBackupsNotifier(service);
});

class DatabaseBackupsNotifier
    extends StateNotifier<AsyncValue<List<DatabaseBackupInfo>>> {
  final DatabaseBackupService? _service;

  DatabaseBackupsNotifier(this._service) : super(const AsyncValue.loading());

  Future<void> loadBackups() async {
    if (_service == null) {
      state = const AsyncValue.data([]);
      return;
    }
    state = const AsyncValue.loading();
    final response = await _service.getBackups();
    if (response.isSuccess && response.data != null) {
      state = AsyncValue.data(response.data!);
    } else {
      state = AsyncValue.error(response.error ?? '加载失败', StackTrace.current);
    }
  }

  Future<bool> createBackup({String? name}) async {
    if (_service == null) return false;
    final response = await _service.createBackup(name: name);
    if (response.isSuccess) {
      await loadBackups();
      return true;
    }
    return false;
  }

  Future<bool> rollback(String backupName) async {
    if (_service == null) return false;
    final response = await _service.rollback(backupName);
    return response.isSuccess;
  }

  Future<bool> deleteBackup(String backupName) async {
    if (_service == null) return false;
    final response = await _service.deleteBackup(backupName);
    if (response.isSuccess) {
      await loadBackups();
      return true;
    }
    return false;
  }
}
