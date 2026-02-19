import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/models.dart';
import '../data/services/api_client.dart';
import '../data/services/log_service.dart';
import '../data/services/storage_service.dart';
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
    final serverUrl = ref.read(serverUrlProvider);
    if (serverUrl == null || serverUrl.isEmpty) {
      return (false, '服务不可用');
    }

    // 创建临时的 ApiClient（不带 onError 回调），避免触发全局错误通知
    final tempClient = ApiClient(baseUrl: serverUrl);
    final tempService = StorageService(tempClient);

    final response = await tempService.testConnection(
      type: type,
      settings: settings,
    );

    if (response.isSuccess) {
      return (true, null);
    }
    return (false, response.error ?? '连接失败');
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
      importStorages({
    required String data,
    String? password,
  }) async {
    final service = ref.read(storageServiceProvider);
    if (service == null) return (false, null, '服务不可用');

    final response =
        await service.importStorages(data: data, password: password);
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

  Future<void> startScanAll({bool forceScrape = false}) async {
    final service = ref.read(storageServiceProvider);
    if (service == null) return;
    final storages = ref.read(storagesProvider).value ?? [];
    final enabledStorages = storages.where((s) => s.enabled).toList();
    if (enabledStorages.isEmpty) return;

    _cancelled = false;
    state = state.copyWith(
      isScanning: true,
      isDiscovering: true,
      discoveredFiles: 0,
      foundFiles: 0,
      pendingFiles: 0,
      updatedFiles: 0,
      dismissed: false,
    );
    _progresses.clear();

    for (final storage in enabledStorages) {
      await service.startScan(storage.id, forceScrape: forceScrape);
    }

    _pollProgress(enabledStorages.map((s) => s.id).toList());
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
  @override
  ScanState build() => ScanState();

  Future<bool> startScan(int storageId, {bool forceScrape = false}) async {
    final service = ref.read(storageServiceProvider);
    if (service == null) return false;

    final response = await service.startScan(
      storageId,
      forceScrape: forceScrape,
    );

    if (response.isSuccess && response.data != null) {
      state = state.copyWith(
        progresses: {...state.progresses, storageId: response.data!},
        scanning: {...state.scanning, storageId},
      );
      return true;
    }
    return false;
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

      state = state.copyWith(
        progresses: {...state.progresses, storageId: progress},
        scanning: newScanning,
      );
    }
  }

  bool isScanning(int storageId) {
    return state.scanning.contains(storageId);
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
    LogService.instance.warn('StorageProvider', 'Failed to invalidate provider: $e');
  }
}

Future<void> browseStorage(WidgetRef ref, int storageId, String path) async {
  final service = ref.read(storageServiceProvider);
  if (service == null) return;

  final requestSeq = (_browseRequestSeq[storageId] ?? 0) + 1;
  _browseRequestSeq[storageId] = requestSeq;

  final currentState = _browseCache[storageId] ?? BrowseState();
  _updateBrowseState(
    storageId,
    currentState.copyWith(isLoading: true, error: null, currentPath: path),
  );
  _safeInvalidate(ref, browseProvider(storageId));

  final response = await service.browseStorage(storageId, path: path);

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
      latestState.copyWith(isLoading: false, error: response.error),
    );
  }
  _safeInvalidate(ref, browseProvider(storageId));
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
