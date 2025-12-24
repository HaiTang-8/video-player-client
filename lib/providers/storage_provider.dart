import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/models.dart';
import '../data/services/storage_service.dart';
import 'server_provider.dart';

/// StorageService Provider
final storageServiceProvider = Provider<StorageService?>((ref) {
  final client = ref.watch(apiClientProvider);
  if (client == null) return null;
  return StorageService(client);
});

/// 存储源列表 Provider
final storagesProvider =
    StateNotifierProvider<StoragesNotifier, AsyncValue<List<Storage>>>((ref) {
  final service = ref.watch(storageServiceProvider);
  return StoragesNotifier(service);
});

class StoragesNotifier extends StateNotifier<AsyncValue<List<Storage>>> {
  final StorageService? _service;

  StoragesNotifier(this._service) : super(const AsyncValue.loading());

  /// 加载存储源列表
  Future<void> loadStorages() async {
    if (_service == null) {
      state = const AsyncValue.data([]);
      return;
    }

    state = const AsyncValue.loading();
    final response = await _service.getStorages();

    if (response.isSuccess && response.data != null) {
      state = AsyncValue.data(response.data!);
    } else {
      state = AsyncValue.error(
        response.error ?? '加载失败',
        StackTrace.current,
      );
    }
  }

  /// 添加存储源
  Future<bool> addStorage({
    required String name,
    required String type,
    required Map<String, String> settings,
  }) async {
    if (_service == null) return false;

    final response = await _service.addStorage(
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

  /// 删除存储源
  Future<bool> deleteStorage(int id) async {
    if (_service == null) return false;

    final response = await _service.deleteStorage(id);

    if (response.isSuccess) {
      await loadStorages();
      return true;
    }
    return false;
  }
}

/// 扫描进度状态
class ScanState {
  final Map<int, ScanProgress> progresses;
  final Set<int> scanning;

  ScanState({
    this.progresses = const {},
    this.scanning = const {},
  });

  ScanState copyWith({
    Map<int, ScanProgress>? progresses,
    Set<int>? scanning,
  }) {
    return ScanState(
      progresses: progresses ?? this.progresses,
      scanning: scanning ?? this.scanning,
    );
  }
}

/// 扫描状态 Provider
final scanStateProvider =
    StateNotifierProvider<ScanStateNotifier, ScanState>((ref) {
  final service = ref.watch(storageServiceProvider);
  return ScanStateNotifier(service);
});

class ScanStateNotifier extends StateNotifier<ScanState> {
  final StorageService? _service;

  ScanStateNotifier(this._service) : super(ScanState());

  /// 启动扫描
  Future<bool> startScan(int storageId) async {
    if (_service == null) return false;

    final response = await _service.startScan(storageId);

    if (response.isSuccess && response.data != null) {
      state = state.copyWith(
        progresses: {...state.progresses, storageId: response.data!},
        scanning: {...state.scanning, storageId},
      );
      return true;
    }
    return false;
  }

  /// 获取扫描进度
  Future<void> refreshProgress(int storageId) async {
    if (_service == null) return;

    final response = await _service.getScanProgress(storageId);

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

  /// 检查是否正在扫描
  bool isScanning(int storageId) {
    return state.scanning.contains(storageId);
  }
}

/// 目录浏览状态
class BrowseState {
  final List<FileInfo> files;
  final String currentPath;
  final bool isLoading;
  final String? error;

  BrowseState({
    this.files = const [],
    this.currentPath = '/',
    this.isLoading = false,
    this.error,
  });

  BrowseState copyWith({
    List<FileInfo>? files,
    String? currentPath,
    bool? isLoading,
    String? error,
  }) {
    return BrowseState(
      files: files ?? this.files,
      currentPath: currentPath ?? this.currentPath,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

/// 目录浏览 Provider（按存储源 ID）
final browseProvider = StateNotifierProvider.family<BrowseNotifier, BrowseState, int>(
    (ref, storageId) {
  final service = ref.watch(storageServiceProvider);
  return BrowseNotifier(service, storageId);
});

class BrowseNotifier extends StateNotifier<BrowseState> {
  final StorageService? _service;
  final int _storageId;

  BrowseNotifier(this._service, this._storageId) : super(BrowseState());

  /// 浏览目录
  Future<void> browse(String path) async {
    if (_service == null) return;

    state = state.copyWith(isLoading: true, error: null, currentPath: path);

    final response = await _service.browseStorage(_storageId, path: path);

    if (response.isSuccess && response.data != null) {
      state = state.copyWith(
        files: response.data!,
        isLoading: false,
      );
    } else {
      state = state.copyWith(
        isLoading: false,
        error: response.error,
      );
    }
  }

  /// 进入子目录
  Future<void> enterDirectory(String dirName) async {
    final newPath = state.currentPath == '/'
        ? '/$dirName'
        : '${state.currentPath}/$dirName';
    await browse(newPath);
  }

  /// 返回上级目录
  Future<void> goBack() async {
    if (state.currentPath == '/') return;

    final parts = state.currentPath.split('/');
    parts.removeLast();
    final newPath = parts.isEmpty ? '/' : parts.join('/');
    await browse(newPath.isEmpty ? '/' : newPath);
  }
}
