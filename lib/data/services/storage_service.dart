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
      fromJson:
          (json) =>
              (json as List)
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
      data: {'name': name, 'type': type, 'settings': settings},
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
      fromJson:
          (json) =>
              (json as List)
                  .map((e) => ScanProgress.fromJson(e as Map<String, dynamic>))
                  .toList(),
    );
  }

  /// 取消扫描任务
  Future<ApiResponse<void>> cancelScan(int taskId) async {
    return _client.post(ApiConstants.taskCancel(taskId));
  }

  /// 取消所有扫描任务
  Future<ApiResponse<void>> cancelAllScans() async {
    return _client.post(ApiConstants.tasksCancelAll);
  }

  /// 浏览目录
  Future<ApiResponse<List<FileInfo>>> browseStorage(
    int storageId, {
    String path = '/',
  }) async {
    return _client.get<List<FileInfo>>(
      ApiConstants.storageBrowse(storageId),
      queryParameters: {'path': path},
      fromJson:
          (json) =>
              (json as List)
                  .map((e) => FileInfo.fromJson(e as Map<String, dynamic>))
                  .toList(),
    );
  }

  /// AI 整理预览：只生成建议方案，不会修改文件
  Future<ApiResponse<AiTidyPlan>> aiTidyPreview(
    int storageId, {
    required String path,
    int maxFiles = 500,
    String? model,
  }) async {
    return _client.post<AiTidyPlan>(
      ApiConstants.storageAiTidyPreview(storageId),
      data: {
        'path': path,
        'max_files': maxFiles,
        if (model != null && model.trim().isNotEmpty) 'model': model.trim(),
      },
      // LLM 调用 + 目录扫描可能超过默认 30s，这里单独放宽接收超时
      receiveTimeout: const Duration(seconds: 180),
      fromJson: (json) => AiTidyPlan.fromJson(json as Map<String, dynamic>),
    );
  }

  /// AI 整理应用：需要用户二次确认后执行，会对文件做移动/重命名
  Future<ApiResponse<AiTidyApplyResult>> aiTidyApply(
    int storageId, {
    required String path,
    required String snapshotHash,
    required List<AiTidyOperation> operations,
  }) async {
    return _client.post<AiTidyApplyResult>(
      ApiConstants.storageAiTidyApply(storageId),
      data: {
        'path': path,
        'snapshot_hash': snapshotHash,
        'operations': operations.map((e) => e.toJson()).toList(),
      },
      // 文件移动/重命名在大量文件时也可能较慢，放宽一点避免误判超时
      receiveTimeout: const Duration(seconds: 300),
      fromJson:
          (json) => AiTidyApplyResult.fromJson(json as Map<String, dynamic>),
    );
  }

  /// 健康检查
  Future<ApiResponse<void>> healthCheck() async {
    return _client.get(ApiConstants.health);
  }
}
