import '../models/models.dart';
import '../../core/constants/api_constants.dart';
import 'api_client.dart';

/// 存储源服务
class StorageService {
  final ApiClient _client;

  StorageService(this._client);

  /// 获取存储源列表
  Future<ApiResponse<List<Storage>>> getStorages() async {
    return _client.get<List<Storage>>(
      ApiConstants.storages,
      fromJson: (json) => (json as List)
          .map((e) => Storage.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  /// 添加存储源
  Future<ApiResponse<Storage>> addStorage({
    required String name,
    required String type,
    required Map<String, String> settings,
  }) async {
    return _client.post<Storage>(
      ApiConstants.storages,
      data: {
        'name': name,
        'type': type,
        'settings': settings,
      },
      fromJson: (json) => Storage.fromJson(json as Map<String, dynamic>),
    );
  }

  /// 删除存储源
  Future<ApiResponse<void>> deleteStorage(int id) async {
    return _client.delete(ApiConstants.storageDetail(id));
  }

  /// 启动扫描
  Future<ApiResponse<ScanProgress>> startScan(int storageId) async {
    return _client.post<ScanProgress>(
      ApiConstants.storageScan(storageId),
      fromJson: (json) => ScanProgress.fromJson(json as Map<String, dynamic>),
    );
  }

  /// 获取扫描进度
  Future<ApiResponse<ScanProgress>> getScanProgress(int storageId) async {
    return _client.get<ScanProgress>(
      ApiConstants.storageScanProgress(storageId),
      fromJson: (json) => ScanProgress.fromJson(json as Map<String, dynamic>),
    );
  }

  /// 获取扫描历史
  Future<ApiResponse<List<ScanProgress>>> getScanTasks(int storageId) async {
    return _client.get<List<ScanProgress>>(
      ApiConstants.storageScanTasks(storageId),
      fromJson: (json) => (json as List)
          .map((e) => ScanProgress.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  /// 浏览目录
  Future<ApiResponse<List<FileInfo>>> browseStorage(
    int storageId, {
    String path = '/',
  }) async {
    return _client.get<List<FileInfo>>(
      ApiConstants.storageBrowse(storageId),
      queryParameters: {'path': path},
      fromJson: (json) => (json as List)
          .map((e) => FileInfo.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  /// 健康检查
  Future<ApiResponse<void>> healthCheck() async {
    return _client.get(ApiConstants.health);
  }
}
