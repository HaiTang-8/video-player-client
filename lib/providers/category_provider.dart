import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/models.dart';
import 'media_provider.dart';
import 'server_provider.dart';

class CategoriesState {
  final List<CategoryStats> categories;
  final bool isLoading;
  final String? error;

  CategoriesState({
    this.categories = const [],
    this.isLoading = false,
    this.error,
  });

  CategoriesState copyWith({
    List<CategoryStats>? categories,
    bool? isLoading,
    String? error,
  }) {
    return CategoriesState(
      categories: categories ?? this.categories,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

final categoriesProvider = NotifierProvider<CategoriesNotifier, CategoriesState>(CategoriesNotifier.new);

class CategoriesNotifier extends Notifier<CategoriesState> {
  @override
  CategoriesState build() {
    ref.watch(serverUrlProvider);
    return CategoriesState();
  }

  Future<void> load() async {
    final serverUrl = ref.read(serverUrlProvider);
    final service = ref.read(mediaServiceProvider);
    if (service == null) return;
    if (state.isLoading) return;

    state = state.copyWith(isLoading: true, error: null);

    final response = await service.getCategories();

    if (ref.read(serverUrlProvider) != serverUrl) return;

    if (response.isSuccess && response.data != null) {
      state = state.copyWith(
        categories: response.data!,
        isLoading: false,
      );
    } else {
      state = state.copyWith(
        isLoading: false,
        error: response.error,
      );
    }
  }

  Future<void> refresh() async {
    clearAllCategoryCache();
    state = CategoriesState();
    await load();
  }
}

class CategoryItemsState {
  final List<MediaItem> items;
  final bool isLoading;
  final bool hasMore;
  final int currentPage;
  final String? error;

  CategoryItemsState({
    this.items = const [],
    this.isLoading = false,
    this.hasMore = true,
    this.currentPage = 0,
    this.error,
  });

  CategoryItemsState copyWith({
    List<MediaItem>? items,
    bool? isLoading,
    bool? hasMore,
    int? currentPage,
    String? error,
  }) {
    return CategoryItemsState(
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      hasMore: hasMore ?? this.hasMore,
      currentPage: currentPage ?? this.currentPage,
      error: error,
    );
  }
}

String? _cachedServerUrl;
final _categoryItemsCache = <String, CategoryItemsState>{};
int _requestVersion = 0;
final _categoryRequestVersions = <String, int>{};

final categoryItemsProvider = Provider.family<CategoryItemsState, String>((ref, categoryId) {
  return _categoryItemsCache[categoryId] ?? CategoryItemsState();
});

void _updateCategoryItems(String categoryId, CategoryItemsState state) {
  _categoryItemsCache[categoryId] = state;
}

void _validateCacheForServer(String? serverUrl) {
  if (_cachedServerUrl != serverUrl) {
    _categoryItemsCache.clear();
    _categoryRequestVersions.clear();
    _cachedServerUrl = serverUrl;
  }
}

void clearAllCategoryCache() {
  _categoryItemsCache.clear();
  _categoryRequestVersions.clear();
}

Future<void> loadCategoryItems(WidgetRef ref, String categoryId, {int pageSize = 20}) async {
  // 注意：此方法会被 Widget 的生命周期触发（例如列表行 initState 后异步加载）。
  // 异步请求返回时，触发加载的 Widget 可能已经 dispose/unmount，
  // 此时继续使用 `ref`（尤其是 `ref.invalidate`）会触发 Riverpod 的
  // "Using ref when a widget is about to or has been unmounted is unsafe" 异常。
  //
  // 这里在同步阶段通过 `ref.context` 获取 ProviderContainer 并缓存下来，
  // 后续使用 container 读/失效 provider，不再依赖已失效的 BuildContext。
  final container = ProviderScope.containerOf(ref.context, listen: false);
  final serverUrl = container.read(serverUrlProvider);
  _validateCacheForServer(serverUrl);

  final service = container.read(mediaServiceProvider);
  if (service == null) return;

  final currentState = _categoryItemsCache[categoryId] ?? CategoryItemsState();
  if (currentState.isLoading) return;

  final requestVersion = ++_requestVersion;
  _categoryRequestVersions[categoryId] = requestVersion;

  _updateCategoryItems(categoryId, currentState.copyWith(isLoading: true, error: null));
  container.invalidate(categoryItemsProvider(categoryId));

  final response = await service.getCategoryItems(categoryId, page: 1, pageSize: pageSize);

  if (_categoryRequestVersions[categoryId] != requestVersion) return;

  if (response.isSuccess && response.data != null) {
    _updateCategoryItems(categoryId, CategoryItemsState(
      items: response.data!,
      isLoading: false,
      currentPage: 1,
      hasMore: response.data!.length >= pageSize,
    ));
  } else {
    _updateCategoryItems(categoryId, currentState.copyWith(isLoading: false, error: response.error));
  }
  container.invalidate(categoryItemsProvider(categoryId));
}

Future<void> loadMoreCategoryItems(WidgetRef ref, String categoryId, {int pageSize = 20}) async {
  // 同上：用 container 替代 `ref.invalidate`，避免在 Widget 已卸载时访问 `ref`。
  final container = ProviderScope.containerOf(ref.context, listen: false);
  final serverUrl = container.read(serverUrlProvider);
  _validateCacheForServer(serverUrl);

  final service = container.read(mediaServiceProvider);
  if (service == null) return;

  final currentState = _categoryItemsCache[categoryId] ?? CategoryItemsState();
  if (currentState.isLoading || !currentState.hasMore) return;

  final requestVersion = ++_requestVersion;
  _categoryRequestVersions[categoryId] = requestVersion;

  _updateCategoryItems(categoryId, currentState.copyWith(isLoading: true));
  container.invalidate(categoryItemsProvider(categoryId));

  final nextPage = currentState.currentPage + 1;
  final response = await service.getCategoryItems(categoryId, page: nextPage, pageSize: pageSize);

  if (_categoryRequestVersions[categoryId] != requestVersion) return;

  if (response.isSuccess && response.data != null) {
    final latestState = _categoryItemsCache[categoryId] ?? CategoryItemsState();
    _updateCategoryItems(categoryId, CategoryItemsState(
      items: [...latestState.items, ...response.data!],
      isLoading: false,
      currentPage: nextPage,
      hasMore: response.data!.length >= pageSize,
    ));
  } else {
    _updateCategoryItems(categoryId, currentState.copyWith(isLoading: false, error: response.error));
  }
  container.invalidate(categoryItemsProvider(categoryId));
}

Future<void> refreshCategoryItems(WidgetRef ref, String categoryId, {int pageSize = 20}) async {
  // 同上：先拿到 container，确保后续 invalidate 不依赖 Widget 是否仍挂载。
  final container = ProviderScope.containerOf(ref.context, listen: false);
  _categoryRequestVersions[categoryId] = ++_requestVersion;
  _categoryItemsCache.remove(categoryId);
  container.invalidate(categoryItemsProvider(categoryId));
  await loadCategoryItems(ref, categoryId, pageSize: pageSize);
}
