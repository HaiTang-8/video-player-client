import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/models.dart';
import '../data/services/database_backup_service.dart';
import 'server_provider.dart';

final databaseBackupServiceProvider = Provider<DatabaseBackupService?>((ref) {
  final client = ref.watch(apiClientProvider);
  if (client == null) return null;
  return DatabaseBackupService(client);
});

final databaseBackupsProvider = NotifierProvider<DatabaseBackupsNotifier, AsyncValue<List<DatabaseBackupInfo>>>(DatabaseBackupsNotifier.new);

class DatabaseBackupsNotifier extends Notifier<AsyncValue<List<DatabaseBackupInfo>>> {
  @override
  AsyncValue<List<DatabaseBackupInfo>> build() => const AsyncValue.loading();

  Future<void> loadBackups() async {
    final service = ref.read(databaseBackupServiceProvider);
    if (service == null) {
      state = const AsyncValue.data([]);
      return;
    }
    state = const AsyncValue.loading();
    final response = await service.getBackups();
    if (response.isSuccess && response.data != null) {
      state = AsyncValue.data(response.data!);
    } else {
      state = AsyncValue.error(response.error ?? '加载失败', StackTrace.current);
    }
  }

  Future<bool> createBackup({String? name}) async {
    final service = ref.read(databaseBackupServiceProvider);
    if (service == null) return false;
    final response = await service.createBackup(name: name);
    if (response.isSuccess) {
      await loadBackups();
      return true;
    }
    return false;
  }

  Future<bool> rollback(String backupName) async {
    final service = ref.read(databaseBackupServiceProvider);
    if (service == null) return false;
    final response = await service.rollback(backupName);
    return response.isSuccess;
  }

  Future<bool> deleteBackup(String backupName) async {
    final service = ref.read(databaseBackupServiceProvider);
    if (service == null) return false;
    final response = await service.deleteBackup(backupName);
    if (response.isSuccess) {
      await loadBackups();
      return true;
    }
    return false;
  }
}
