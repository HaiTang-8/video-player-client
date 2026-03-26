import 'dart:convert';

import 'package:dio/dio.dart';

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

  /// 启用存储源
  Future<ApiResponse<void>> enableStorage(int id) async {
    return _client.post(ApiConstants.storageEnable(id));
  }

  /// 禁用存储源
  Future<ApiResponse<void>> disableStorage(
    int id, {
    bool hideMedia = false,
  }) async {
    return _client.post(
      ApiConstants.storageDisable(id),
      data: {'hide_media': hideMedia},
    );
  }

  /// 更新存储源
  Future<ApiResponse<Storage>> updateStorage({
    required int id,
    required String name,
    required String type,
    required Map<String, String> settings,
  }) async {
    return _client.put<Storage>(
      ApiConstants.storageDetail(id),
      data: {'name': name, 'type': type, 'settings': settings},
      fromJson: (json) => Storage.fromJson(json as Map<String, dynamic>),
    );
  }

  /// 测试存储源连接
  Future<ApiResponse<void>> testConnection({
    required String type,
    required Map<String, String> settings,
  }) async {
    return _client.post(
      ApiConstants.storageTestConnection,
      data: {'type': type, 'settings': settings},
    );
  }

  /// 启动扫描
  Future<ApiResponse<ScanProgress>> startScan(
    int storageId, {
    bool forceScrape = false,
    String? path,
  }) async {
    final payload = <String, dynamic>{};
    if (forceScrape) {
      payload['force_scrape'] = true;
    }
    final normalizedPath = path?.trim();
    if (normalizedPath != null &&
        normalizedPath.isNotEmpty &&
        normalizedPath != '/') {
      payload['path'] = normalizedPath;
    }

    return _client.post<ScanProgress>(
      ApiConstants.storageScan(storageId),
      data: payload.isEmpty ? null : payload,
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

  Stream<ScanProgress> streamScanProgress(
    int storageId, {
    required int taskId,
    CancelToken? cancelToken,
  }) async* {
    final dataLines = <String>[];

    await for (final line in _client.openEventStream(
      ApiConstants.storageScanProgressStream(storageId),
      queryParameters: {'task_id': taskId},
      receiveTimeout: const Duration(minutes: 10),
      cancelToken: cancelToken,
    )) {
      if (line.isEmpty) {
        if (dataLines.isEmpty) continue;
        final payload = dataLines.join('\n');
        dataLines.clear();
        final decoded = jsonDecode(payload);
        if (decoded is Map<String, dynamic>) {
          yield ScanProgress.fromJson(decoded);
        }
        continue;
      }

      if (line.startsWith(':')) continue;
      if (line.startsWith('data:')) {
        dataLines.add(line.substring(5).trimLeft());
      }
    }
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

  /// 强制刷新目录缓存并重新获取目录
  Future<ApiResponse<List<FileInfo>>> refreshBrowseStorage(
    int storageId, {
    String path = '/',
  }) async {
    return _client.post<List<FileInfo>>(
      ApiConstants.storageBrowseRefresh(storageId),
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
    bool enableTmdb = false,
    int? maxTmdbQueries,
    String? folderMode,
  }) async {
    return _client.post<AiTidyPlan>(
      ApiConstants.storageAiTidyPreview(storageId),
      data: {
        'path': path,
        'max_files': maxFiles,
        if (model != null && model.trim().isNotEmpty) 'model': model.trim(),
        'enable_tmdb': enableTmdb,
        if (maxTmdbQueries != null && maxTmdbQueries > 0)
          'max_tmdb_queries': maxTmdbQueries,
        if (folderMode != null && folderMode.trim().isNotEmpty)
          'folder_mode': folderMode.trim(),
      },
      // LLM 调用 + 目录扫描 + TMDB 查询可能超过默认 30s，这里单独放宽接收超时
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

  /// 获取黑名单（分页）
  Future<ApiResponse<List<String>>> getBlacklist(
    int storageId, {
    int page = 1,
    int pageSize = 10,
    String? keyword,
  }) async {
    final queryParams = <String, dynamic>{'page': page, 'page_size': pageSize};
    if (keyword != null && keyword.isNotEmpty) {
      queryParams['keyword'] = keyword;
    }
    return _client.get<List<String>>(
      ApiConstants.storageBlacklist(storageId),
      queryParameters: queryParams,
      fromJson: (json) {
        final data = json as Map<String, dynamic>;
        final blacklist = data['blacklist'] as List? ?? [];
        return blacklist
            .map((e) {
              if (e is String) return e;
              if (e is Map<String, dynamic>) return e['path'] as String? ?? '';
              return e.toString();
            })
            .where((e) => e.isNotEmpty)
            .toList();
      },
    );
  }

  /// 添加到黑名单
  Future<ApiResponse<void>> addToBlacklist(int storageId, String path) async {
    return _client.post(
      ApiConstants.storageBlacklistAdd(storageId),
      data: {'path': path},
    );
  }

  /// 从黑名单移除
  Future<ApiResponse<void>> removeFromBlacklist(
    int storageId,
    String path,
  ) async {
    return _client.post(
      ApiConstants.storageBlacklistRemove(storageId),
      data: {'path': path},
    );
  }

  /// 设置黑名单（批量操作）
  Future<ApiResponse<void>> setBlacklist(
    int storageId,
    List<String> blacklist,
  ) async {
    return _client.put(
      ApiConstants.storageBlacklist(storageId),
      data: {'blacklist': blacklist},
    );
  }

  /// 导出存储源
  Future<ApiResponse<String>> exportStorages({String? password}) async {
    final queryParams = <String, dynamic>{};
    if (password != null && password.isNotEmpty) {
      queryParams['password'] = password;
    }
    return _client.get<String>(
      ApiConstants.storageExport,
      queryParameters: queryParams.isNotEmpty ? queryParams : null,
      fromJson: (json) => (json as Map<String, dynamic>)['data'] as String,
    );
  }

  /// 导入存储源
  Future<ApiResponse<StorageImportResult>> importStorages({
    required String data,
    String? password,
  }) async {
    return _client.post<StorageImportResult>(
      ApiConstants.storageImport,
      data: {
        'data': data,
        if (password != null && password.isNotEmpty) 'password': password,
      },
      fromJson:
          (json) => StorageImportResult.fromJson(json as Map<String, dynamic>),
    );
  }

  /// 健康检查
  Future<ApiResponse<void>> healthCheck() async {
    return _client.get(ApiConstants.health);
  }
}
