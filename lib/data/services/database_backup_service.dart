import '../models/models.dart';
import '../../core/constants/api_constants.dart';
import 'api_client.dart';

class DatabaseBackupService {
  final ApiClient _client;

  DatabaseBackupService(this._client);

  Future<ApiResponse<List<DatabaseBackupInfo>>> getBackups() async {
    return _client.get<List<DatabaseBackupInfo>>(
      ApiConstants.databaseBackups,
      fromJson:
          (json) =>
              (json as List)
                  .map(
                    (e) =>
                        DatabaseBackupInfo.fromJson(e as Map<String, dynamic>),
                  )
                  .toList(),
    );
  }

  Future<ApiResponse<DatabaseBackupInfo>> createBackup({String? name}) async {
    return _client.post<DatabaseBackupInfo>(
      ApiConstants.databaseBackups,
      data: name != null ? {'name': name} : {},
      fromJson:
          (json) => DatabaseBackupInfo.fromJson(json as Map<String, dynamic>),
    );
  }

  Future<ApiResponse<void>> rollback(String backupName) async {
    return _client.post<void>(
      ApiConstants.databaseRollback,
      data: {'backup': backupName},
    );
  }

  Future<ApiResponse<void>> deleteBackup(String backupName) async {
    return _client.delete<void>(ApiConstants.databaseBackupDelete(backupName));
  }
}
