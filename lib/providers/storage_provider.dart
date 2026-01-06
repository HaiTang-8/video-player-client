import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/models.dart';
import '../data/services/storage_service.dart';
import 'server_provider.dart';

final storageServiceProvider = Provider<StorageService?>((ref) {
  final client = ref.watch(apiClientProvider);
  if (client == null) return null;
  return StorageService(client);
});

final storagesProvider = NotifierProvider<StoragesNotifier, AsyncValue<List<Storage>>>(StoragesNotifier.new);

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

    final response = await service.addStorage(name: name, type: type, settings: settings);

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

    final response = await service.updateStorage(id: id, name: name, type: type, settings: settings);

    if (response.isSuccess) {
      await loadStorages();
      return true;
    }
    return false;
  }
}

class GlobalScanState {
  final bool isScanning;
  final int foundFiles;
  final int pendingFiles;
  final int updatedFiles;
  final bool dismissed;

  const GlobalScanState({
    this.isScanning = false,
    this.foundFiles = 0,
    this.pendingFiles = 0,
    this.updatedFiles = 0,
    this.dismissed = false,
  });

  GlobalScanState copyWith({
    bool? isScanning,
    int? foundFiles,
    int? pendingFiles,
    int? updatedFiles,
    bool? dismissed,
  }) {
    return GlobalScanState(
      isScanning: isScanning ?? this.isScanning,
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

final scanStateProvider = NotifierProvider<ScanStateNotifier, ScanState>(ScanStateNotifier.new);

final globalScanStateProvider = NotifierProvider<GlobalScanNotifier, GlobalScanState>(GlobalScanNotifier.new);

class GlobalScanNotifier extends Notifier<GlobalScanState> {
  final Map<int, ScanProgress> _progresses = {};
  bool _cancelled = false;

  @override
  GlobalScanState build() => const GlobalScanState();

  Future<void> startScanAll({bool forceScrape = false}) async {
    final service = ref.read(storageServiceProvider);
    if (service == null) return;
    final storages = ref.read(storagesProvider).value ?? [];
    if (storages.isEmpty) return;

    _cancelled = false;
    state = state.copyWith(isScanning: true, foundFiles: 0, pendingFiles: 0, updatedFiles: 0, dismissed: false);
    _progresses.clear();

    for (final storage in storages) {
      await service.startScan(storage.id, forceScrape: forceScrape);
    }

    _pollProgress(storages.map((s) => s.id).toList());
  }

  void _pollProgress(List<int> storageIds) async {
    final service = ref.read(storageServiceProvider);
    if (service == null) return;

    while (state.isScanning && !_cancelled) {
      await Future.delayed(const Duration(seconds: 1));

      if (_cancelled) break;

      int totalFound = 0, totalUpdated = 0;
      bool anyRunning = false;

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
        totalFound += p.totalFiles;
        totalUpdated += p.scannedFiles;
      }

      state = state.copyWith(
        foundFiles: totalFound,
        pendingFiles: totalFound - totalUpdated,
        updatedFiles: totalUpdated,
        isScanning: anyRunning,
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

    final response = await service.startScan(storageId, forceScrape: forceScrape);

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

final _browseCache = <int, BrowseState>{};

final browseProvider = Provider.family<BrowseState, int>((ref, storageId) {
  return _browseCache[storageId] ?? BrowseState();
});

void _updateBrowseState(int storageId, BrowseState state) {
  _browseCache[storageId] = state;
}

Future<void> browseStorage(WidgetRef ref, int storageId, String path) async {
  final service = ref.read(storageServiceProvider);
  if (service == null) return;

  final currentState = _browseCache[storageId] ?? BrowseState();
  _updateBrowseState(storageId, currentState.copyWith(isLoading: true, error: null, currentPath: path));
  ref.invalidate(browseProvider(storageId));

  final response = await service.browseStorage(storageId, path: path);

  if (response.isSuccess && response.data != null) {
    _updateBrowseState(storageId, BrowseState(files: response.data!, currentPath: path, isLoading: false));
  } else {
    _updateBrowseState(storageId, currentState.copyWith(isLoading: false, error: response.error, currentPath: path));
  }
  ref.invalidate(browseProvider(storageId));
}

Future<void> enterDirectory(WidgetRef ref, int storageId, String dirName) async {
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
