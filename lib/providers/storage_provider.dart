import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/models.dart';
import '../data/services/api_client.dart';
import '../data/services/log_service.dart';
import '../data/services/storage_service.dart';
import 'auth_provider.dart';
import 'server_provider.dart';

final storageServiceProvider = Provider<StorageService?>((ref) {
  final client = ref.watch(apiClientProvider);
  if (client == null) return null;
  return StorageService(client);
});

final storagesProvider =
    NotifierProvider<StoragesNotifier, AsyncValue<List<Storage>>>(
      StoragesNotifier.new,
    );

class StoragesNotifier extends Notifier<AsyncValue<List<Storage>>> {
  @override
  AsyncValue<List<Storage>> build() => const AsyncValue.loading();

  Future<void> loadStorages() async {
    final service = ref.read(storageServiceProvider);
    if (service == null) {
      state = const AsyncValue.data([]);
      return;
    }

    state = const AsyncValue.loading();
    final response = await service.getStorages();

    if (response.isSuccess && response.data != null) {
      state = AsyncValue.data(response.data!);
    } else {
      state = AsyncValue.error(response.error ?? '加载失败', StackTrace.current);
    }
  }

  Future<bool> addStorage({
    required String name,
    required String type,
    required Map<String, String> settings,
  }) async {
    final service = ref.read(storageServiceProvider);
    if (service == null) return false;

    final response = await service.addStorage(
      name: name,
      type: type,
      settings: settings,
    );

    if (response.isSuccess) {
      await loadStorages();
      return true;
    }
    return false;
  }

  Future<bool> deleteStorage(int id) async {
    final service = ref.read(storageServiceProvider);
    if (service == null) return false;

    final response = await service.deleteStorage(id);

    if (response.isSuccess) {
      await loadStorages();
      return true;
    }
    return false;
  }

  Future<bool> updateStorage({
    required int id,
    required String name,
    required String type,
    required Map<String, String> settings,
  }) async {
    final service = ref.read(storageServiceProvider);
    if (service == null) return false;

    final response = await service.updateStorage(
      id: id,
      name: name,
      type: type,
      settings: settings,
    );

    if (response.isSuccess) {
      await loadStorages();
      return true;
    }
    return false;
  }

  Future<bool> enableStorage(int id) async {
    final service = ref.read(storageServiceProvider);
    if (service == null) return false;

    final response = await service.enableStorage(id);

    if (response.isSuccess) {
      await loadStorages();
      return true;
    }
    return false;
  }

  Future<bool> disableStorage(int id, {bool hideMedia = false}) async {
    final service = ref.read(storageServiceProvider);
    if (service == null) return false;

    final response = await service.disableStorage(id, hideMedia: hideMedia);

    if (response.isSuccess) {
      await loadStorages();
      return true;
    }
    return false;
  }

  Future<(bool success, String? error)> testConnection({
    required String type,
    required Map<String, String> settings,
  }) async {
    final server = ref.read(serverListProvider).currentServer;
    if (server == null || server.url.isEmpty) {
      return (false, '服务不可用');
    }

    final tempClient = ApiClient(
      baseUrl: server.url,
      proxyUrl: server.proxyUrl,
    );
    tempClient.addInterceptor(
      AuthInterceptor(
        tokenGetter: () => ref.read(authProvider).tokens?.accessToken,
        onTokenExpired: () => ref.read(authProvider.notifier).refreshToken(),
      ),
    );
    try {
      final tempService = StorageService(tempClient);
      final response = await tempService.testConnection(
        type: type,
        settings: settings,
      );

      if (response.isSuccess) {
        return (true, null);
      }
      return (false, response.error ?? '连接失败');
    } finally {
      tempClient.close();
    }
  }

  Future<(bool success, String? data, String? error)> exportStorages({
    String? password,
  }) async {
    final service = ref.read(storageServiceProvider);
    if (service == null) return (false, null, '服务不可用');

    final response = await service.exportStorages(password: password);
    if (response.isSuccess && response.data != null) {
      return (true, response.data, null);
    }
    return (false, null, response.error ?? '导出失败');
  }

  Future<(bool success, StorageImportResult? result, String? error)>
  importStorages({required String data, String? password}) async {
    final service = ref.read(storageServiceProvider);
    if (service == null) return (false, null, '服务不可用');

    final response = await service.importStorages(
      data: data,
      password: password,
    );
    if (response.isSuccess && response.data != null) {
      await loadStorages();
      return (true, response.data, null);
    }
    return (false, null, response.error ?? '导入失败');
  }
}

class GlobalScanState {
  final bool isScanning;
  final bool isDiscovering;
  final int discoveredFiles;
  final int foundFiles;
  final int pendingFiles;
  final int updatedFiles;
  final bool dismissed;

  const GlobalScanState({
    this.isScanning = false,
    this.isDiscovering = false,
    this.discoveredFiles = 0,
    this.foundFiles = 0,
    this.pendingFiles = 0,
    this.updatedFiles = 0,
    this.dismissed = false,
  });

  GlobalScanState copyWith({
    bool? isScanning,
    bool? isDiscovering,
    int? discoveredFiles,
    int? foundFiles,
    int? pendingFiles,
    int? updatedFiles,
    bool? dismissed,
  }) {
    return GlobalScanState(
      isScanning: isScanning ?? this.isScanning,
      isDiscovering: isDiscovering ?? this.isDiscovering,
      discoveredFiles: discoveredFiles ?? this.discoveredFiles,
      foundFiles: foundFiles ?? this.foundFiles,
      pendingFiles: pendingFiles ?? this.pendingFiles,
      updatedFiles: updatedFiles ?? this.updatedFiles,
      dismissed: dismissed ?? this.dismissed,
    );
  }
}

class GlobalScanStartResult {
  final bool started;
  final bool partial;
  final String message;

  const GlobalScanStartResult({
    required this.started,
    required this.message,
    this.partial = false,
  });
}

class ScanState {
  final Map<int, ScanProgress> progresses;
  final Set<int> scanning;

  ScanState({this.progresses = const {}, this.scanning = const {}});

  ScanState copyWith({Map<int, ScanProgress>? progresses, Set<int>? scanning}) {
    return ScanState(
      progresses: progresses ?? this.progresses,
      scanning: scanning ?? this.scanning,
    );
  }
}

final scanStateProvider = NotifierProvider<ScanStateNotifier, ScanState>(
  ScanStateNotifier.new,
);

final globalScanStateProvider =
    NotifierProvider<GlobalScanNotifier, GlobalScanState>(
      GlobalScanNotifier.new,
    );

class GlobalScanNotifier extends Notifier<GlobalScanState> {
  final Map<int, ScanProgress> _progresses = {};
  bool _cancelled = false;

  @override
  GlobalScanState build() => const GlobalScanState();

  Future<GlobalScanStartResult> startScanAll({bool forceScrape = false}) async {
    final service = ref.read(storageServiceProvider);
    if (service == null) {
      return const GlobalScanStartResult(started: false, message: '服务不可用');
    }
    final storages = ref.read(storagesProvider).value ?? [];
    final enabledStorages = storages.where((s) => s.enabled).toList();
    if (enabledStorages.isEmpty) {
      return const GlobalScanStartResult(
        started: false,
        message: '没有可扫描的启用存储源',
      );
    }

    _cancelled = false;
    _progresses.clear();
    final startedStorageIds = <int>[];
    final failedStorageNames = <String>[];
    String? firstError;

    for (final storage in enabledStorages) {
      final response = await service.startScan(
        storage.id,
        forceScrape: forceScrape,
      );
      if (response.isSuccess) {
        if (response.data != null) {
          _progresses[storage.id] = response.data!;
        }
        startedStorageIds.add(storage.id);
        continue;
      }
      failedStorageNames.add(storage.name);
      firstError ??= response.error;
    }

    if (startedStorageIds.isEmpty) {
      state = const GlobalScanState();
      return GlobalScanStartResult(
        started: false,
        message: firstError ?? '扫描启动失败',
      );
    }

    state = state.copyWith(
      isScanning: true,
      isDiscovering: true,
      discoveredFiles: 0,
      foundFiles: 0,
      pendingFiles: 0,
      updatedFiles: 0,
      dismissed: false,
    );

    _pollProgress(startedStorageIds);

    if (failedStorageNames.isNotEmpty) {
      return GlobalScanStartResult(
        started: true,
        partial: true,
        message:
            '已启动 ${startedStorageIds.length} 个存储源，${failedStorageNames.length} 个启动失败',
      );
    }

    final message =
        startedStorageIds.length == 1
            ? '已开始扫描'
            : '已开始扫描 ${startedStorageIds.length} 个存储源';
    return GlobalScanStartResult(started: true, message: message);
  }

  void _pollProgress(List<int> storageIds) async {
    final service = ref.read(storageServiceProvider);
    if (service == null) return;

    while (state.isScanning && !_cancelled) {
      await Future.delayed(const Duration(seconds: 1));

      if (_cancelled) break;

      int totalFound = 0, totalUpdated = 0, totalDiscovered = 0;
      bool anyRunning = false;
      bool anyDiscovering = false;

      for (final id in storageIds) {
        if (_cancelled) break;
        final response = await service.getScanProgress(id);
        if (response.isSuccess && response.data != null) {
          _progresses[id] = response.data!;
          if (response.data!.isRunning) anyRunning = true;
        }
      }

      if (_cancelled) break;

      for (final p in _progresses.values) {
        totalDiscovered += p.discoveredFiles;
        if (p.isDiscovering) {
          anyDiscovering = true;
        } else {
          totalFound += p.totalFiles;
          totalUpdated += p.scannedFiles;
        }
      }

      state = state.copyWith(
        foundFiles: totalFound,
        pendingFiles: totalFound - totalUpdated,
        updatedFiles: totalUpdated,
        isScanning: anyRunning,
        isDiscovering: anyDiscovering,
        discoveredFiles: totalDiscovered,
      );

      if (!anyRunning) break;
    }
  }

  void dismiss() {
    state = state.copyWith(dismissed: true);
  }

  void showPopover() {
    state = state.copyWith(dismissed: false);
  }

  Future<void> cancelAllScans() async {
    final service = ref.read(storageServiceProvider);
    if (service == null) return;

    _cancelled = true;
    await service.cancelAllScans();

    state = const GlobalScanState();
    _progresses.clear();
  }
}

class ScanStateNotifier extends Notifier<ScanState> {
  final Set<int> _polling = {};
  final Map<int, StreamSubscription<ScanProgress>> _liveSubscriptions = {};
  final Map<int, CancelToken> _liveCancelTokens = {};
  final Map<int, int> _autoDismissTaskIds = {};
  static const _successDismissDelay = Duration(seconds: 3);

  @override
  ScanState build() {
    ref.onDispose(() {
      for (final subscription in _liveSubscriptions.values) {
        subscription.cancel();
      }
      for (final cancelToken in _liveCancelTokens.values) {
        if (!cancelToken.isCancelled) {
          cancelToken.cancel('disposed');
        }
      }
      _liveSubscriptions.clear();
      _liveCancelTokens.clear();
    });
    return ScanState();
  }

  Future<(bool success, String? error)> startScan(
    int storageId, {
    bool forceScrape = false,
    String? path,
  }) async {
    final service = ref.read(storageServiceProvider);
    if (service == null) return (false, '服务不可用');

    final response = await service.startScan(
      storageId,
      forceScrape: forceScrape,
      path: path,
    );

    if (response.isSuccess && response.data != null) {
      _cancelLiveProgressSubscription(storageId);
      _autoDismissTaskIds.remove(storageId);
      _updateScanState(storageId, response.data!, {
        ...state.scanning,
        storageId,
      });
      _pollProgress(storageId);
      return (true, null);
    }
    return (false, response.error ?? '启动扫描失败');
  }

  Future<({bool success, String? error, int? taskId})> startPathScanWithSse(
    int storageId, {
    required String path,
    bool forceScrape = false,
  }) async {
    final service = ref.read(storageServiceProvider);
    if (service == null) {
      return (success: false, error: '服务不可用', taskId: null);
    }

    final response = await service.startScan(
      storageId,
      forceScrape: forceScrape,
      path: path,
    );

    if (response.isSuccess && response.data != null) {
      _cancelLiveProgressSubscription(storageId);
      _autoDismissTaskIds.remove(storageId);
      _updateScanState(storageId, response.data!, {
        ...state.scanning,
        storageId,
      });

      final taskId = response.data!.taskId;
      if (taskId > 0) {
        _streamPathScanProgress(storageId, taskId);
      } else {
        _pollProgress(storageId);
      }
      return (success: true, error: null, taskId: taskId > 0 ? taskId : null);
    }
    return (success: false, error: response.error ?? '启动扫描失败', taskId: null);
  }

  void _pollProgress(int storageId) async {
    if (_polling.contains(storageId)) return;
    _polling.add(storageId);

    final service = ref.read(storageServiceProvider);
    if (service == null) {
      _polling.remove(storageId);
      return;
    }

    while (state.scanning.contains(storageId)) {
      final response = await service.getScanProgress(storageId);
      if (response.isSuccess && response.data != null) {
        final progress = response.data!;
        final newScanning = Set<int>.from(state.scanning);
        if (!progress.isRunning) {
          newScanning.remove(storageId);
        }
        _updateScanState(storageId, progress, newScanning);
      }
      if (!state.scanning.contains(storageId)) break;
      await Future.delayed(const Duration(seconds: 1));
    }

    _polling.remove(storageId);
  }

  Future<void> refreshProgress(int storageId) async {
    final service = ref.read(storageServiceProvider);
    if (service == null) return;

    final response = await service.getScanProgress(storageId);

    if (response.isSuccess && response.data != null) {
      final progress = response.data!;
      final newScanning = Set<int>.from(state.scanning);

      if (!progress.isRunning) {
        newScanning.remove(storageId);
      }

      _updateScanState(storageId, progress, newScanning);
    }
  }

  bool isScanning(int storageId) {
    return state.scanning.contains(storageId);
  }

  Future<({bool success, String? error})> cancelScan(int storageId) async {
    final progress = state.progresses[storageId];
    if (progress == null) {
      return (success: false, error: '未找到扫描任务');
    }
    final service = ref.read(storageServiceProvider);
    if (service == null) {
      return (success: false, error: '服务不可用');
    }
    final response = await service.cancelScan(progress.taskId);
    if (!response.isSuccess) {
      final error = response.error ?? '取消扫描失败';
      LogService.instance.warn(
        'PathScanSse',
        'Cancel scan failed for storage $storageId task ${progress.taskId}: $error',
      );
      return (success: false, error: error);
    }
    _removeProgress(storageId);
    return (success: true, error: null);
  }

  void _streamPathScanProgress(int storageId, int taskId) {
    final service = ref.read(storageServiceProvider);
    if (service == null) {
      _pollProgress(storageId);
      return;
    }

    _cancelLiveProgressSubscription(storageId);
    final cancelToken = CancelToken();
    _liveCancelTokens[storageId] = cancelToken;

    final subscription = service
        .streamScanProgress(storageId, taskId: taskId, cancelToken: cancelToken)
        .listen(
          (progress) {
            final newScanning = Set<int>.from(state.scanning);
            if (!progress.isRunning) {
              newScanning.remove(storageId);
            }
            _updateScanState(storageId, progress, newScanning);
            if (!newScanning.contains(storageId)) {
              _cancelLiveProgressSubscription(storageId, cancelRequest: false);
            }
          },
          onError: (error, stackTrace) {
            LogService.instance.warn(
              'PathScanSse',
              'SSE failed for storage $storageId task $taskId: $error',
            );
            final shouldFallback =
                state.scanning.contains(storageId) &&
                state.progresses[storageId]?.taskId == taskId;
            _cancelLiveProgressSubscription(storageId);
            if (shouldFallback) {
              _pollProgress(storageId);
            }
          },
          onDone: () {
            if (_liveCancelTokens[storageId] != cancelToken) return;
            _cancelLiveProgressSubscription(storageId, cancelRequest: false);
            if (state.scanning.contains(storageId)) {
              _pollProgress(storageId);
            }
          },
        );

    _liveSubscriptions[storageId] = subscription;
  }

  void _updateScanState(
    int storageId,
    ScanProgress progress,
    Set<int> scanning,
  ) {
    state = state.copyWith(
      progresses: {...state.progresses, storageId: progress},
      scanning: scanning,
    );

    if (scanning.contains(storageId)) {
      _autoDismissTaskIds.remove(storageId);
      return;
    }

    if (_shouldAutoDismiss(progress)) {
      _scheduleAutoDismiss(progress);
    } else {
      _autoDismissTaskIds.remove(storageId);
    }
  }

  bool _shouldAutoDismiss(ScanProgress progress) {
    return progress.isCompleted && progress.error == null;
  }

  void _scheduleAutoDismiss(ScanProgress progress) {
    final storageId = progress.storageId;
    final taskId = progress.taskId;

    if (_autoDismissTaskIds[storageId] == taskId) return;
    _autoDismissTaskIds[storageId] = taskId;

    Future.delayed(_successDismissDelay, () {
      if (_autoDismissTaskIds[storageId] != taskId) return;

      final latest = state.progresses[storageId];
      if (latest == null ||
          latest.taskId != taskId ||
          state.scanning.contains(storageId) ||
          !_shouldAutoDismiss(latest)) {
        return;
      }

      _removeProgress(storageId);
    });
  }

  void _removeProgress(int storageId) {
    _cancelLiveProgressSubscription(storageId);
    _autoDismissTaskIds.remove(storageId);
    final newProgresses = Map<int, ScanProgress>.from(state.progresses)
      ..remove(storageId);
    final newScanning = Set<int>.from(state.scanning)..remove(storageId);
    state = state.copyWith(progresses: newProgresses, scanning: newScanning);
  }

  void _cancelLiveProgressSubscription(
    int storageId, {
    bool cancelRequest = true,
  }) {
    final subscription = _liveSubscriptions.remove(storageId);
    subscription?.cancel();

    final cancelToken = _liveCancelTokens.remove(storageId);
    if (cancelRequest && cancelToken != null && !cancelToken.isCancelled) {
      cancelToken.cancel('cancelled');
    }
  }
}

class BrowseState {
  final List<FileInfo> files;
  final String currentPath;
  final bool isLoading;
  final String? error;
  final Set<String> blacklist;

  BrowseState({
    this.files = const [],
    this.currentPath = '/',
    this.isLoading = false,
    this.error,
    this.blacklist = const {},
  });

  bool isBlacklisted(String path) {
    return blacklist.any((b) => path == b || path.startsWith('$b/'));
  }

  BrowseState copyWith({
    List<FileInfo>? files,
    String? currentPath,
    bool? isLoading,
    String? error,
    Set<String>? blacklist,
  }) {
    return BrowseState(
      files: files ?? this.files,
      currentPath: currentPath ?? this.currentPath,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      blacklist: blacklist ?? this.blacklist,
    );
  }
}

final _browseCache = <int, BrowseState>{};
final _browseRequestSeq = <int, int>{};

final browseProvider = Provider.family<BrowseState, int>((ref, storageId) {
  return _browseCache[storageId] ?? BrowseState();
});

void _updateBrowseState(int storageId, BrowseState state) {
  _browseCache[storageId] = state;
}

void _safeInvalidate(WidgetRef ref, provider) {
  try {
    ref.invalidate(provider);
  } catch (e) {
    LogService.instance.warn(
      'StorageProvider',
      'Failed to invalidate provider: $e',
    );
  }
}

Future<void> _loadBrowseStorage(
  WidgetRef ref,
  int storageId,
  String path, {
  required bool forceRefresh,
}) async {
  final service = ref.read(storageServiceProvider);
  if (service == null) return;

  final requestSeq = (_browseRequestSeq[storageId] ?? 0) + 1;
  _browseRequestSeq[storageId] = requestSeq;

  final currentState = _browseCache[storageId] ?? BrowseState();
  final previousPath = currentState.currentPath;
  _updateBrowseState(
    storageId,
    currentState.copyWith(isLoading: true, error: null, currentPath: path),
  );
  _safeInvalidate(ref, browseProvider(storageId));

  final response =
      forceRefresh
          ? await service.refreshBrowseStorage(storageId, path: path)
          : await service.browseStorage(storageId, path: path);

  // 如果在等待期间用户发起了新的浏览请求，忽略旧响应，避免覆盖最新状态（尤其是 blacklist）。
  if (_browseRequestSeq[storageId] != requestSeq) return;

  final latestState = _browseCache[storageId] ?? currentState;
  if (response.isSuccess && response.data != null) {
    _updateBrowseState(
      storageId,
      latestState.copyWith(
        files: response.data!,
        currentPath: path,
        isLoading: false,
        error: null,
      ),
    );
  } else {
    _updateBrowseState(
      storageId,
      latestState.copyWith(
        currentPath: previousPath,
        isLoading: false,
        error: response.error,
      ),
    );
  }
  _safeInvalidate(ref, browseProvider(storageId));
}

Future<void> browseStorage(WidgetRef ref, int storageId, String path) async {
  await _loadBrowseStorage(ref, storageId, path, forceRefresh: false);
}

Future<void> refreshBrowseStorage(
  WidgetRef ref,
  int storageId,
  String path,
) async {
  await _loadBrowseStorage(ref, storageId, path, forceRefresh: true);
}

Future<void> enterDirectory(
  WidgetRef ref,
  int storageId,
  String dirName,
) async {
  final currentPath = (_browseCache[storageId] ?? BrowseState()).currentPath;
  final newPath = currentPath == '/' ? '/$dirName' : '$currentPath/$dirName';
  await browseStorage(ref, storageId, newPath);
}

Future<void> goBackDirectory(WidgetRef ref, int storageId) async {
  final currentPath = (_browseCache[storageId] ?? BrowseState()).currentPath;
  if (currentPath == '/') return;

  final parts = currentPath.split('/');
  parts.removeLast();
  final newPath = parts.isEmpty ? '/' : parts.join('/');
  await browseStorage(ref, storageId, newPath.isEmpty ? '/' : newPath);
}

Future<void> loadBlacklist(WidgetRef ref, int storageId) async {
  final service = ref.read(storageServiceProvider);
  if (service == null) return;

  // 获取全部黑名单用于浏览时判断
  final response = await service.getBlacklist(storageId, pageSize: 10000);
  if (response.isSuccess && response.data != null) {
    final currentState = _browseCache[storageId] ?? BrowseState();
    final blacklist =
        response.data!
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty && e != '/')
            .toSet();
    _updateBrowseState(storageId, currentState.copyWith(blacklist: blacklist));
    _safeInvalidate(ref, browseProvider(storageId));
  }
}

Future<bool> addToBlacklist(WidgetRef ref, int storageId, String path) async {
  final service = ref.read(storageServiceProvider);
  if (service == null) return false;

  final response = await service.addToBlacklist(storageId, path);
  if (response.isSuccess) {
    await loadBlacklist(ref, storageId);
    return true;
  }
  return false;
}

Future<bool> removeFromBlacklist(
  WidgetRef ref,
  int storageId,
  String path,
) async {
  final service = ref.read(storageServiceProvider);
  if (service == null) return false;

  final response = await service.removeFromBlacklist(storageId, path);
  if (response.isSuccess) {
    await loadBlacklist(ref, storageId);
    return true;
  }
  return false;
}

Future<bool> clearBlacklist(WidgetRef ref, int storageId) async {
  final service = ref.read(storageServiceProvider);
  if (service == null) return false;

  final response = await service.setBlacklist(storageId, []);
  if (response.isSuccess) {
    await loadBlacklist(ref, storageId);
    return true;
  }
  return false;
}
