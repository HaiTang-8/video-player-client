import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/models.dart';
import 'media_provider.dart';

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
  CategoriesState build() => CategoriesState();

  Future<void> load() async {
    final service = ref.read(mediaServiceProvider);
    if (service == null) return;
    if (state.isLoading) return;

    state = state.copyWith(isLoading: true, error: null);

    final response = await service.getCategories();

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

final _categoryItemsCache = <String, CategoryItemsState>{};

final categoryItemsProvider = Provider.family<CategoryItemsState, String>((ref, categoryId) {
  return _categoryItemsCache[categoryId] ?? CategoryItemsState();
});

void _updateCategoryItems(String categoryId, CategoryItemsState state) {
  _categoryItemsCache[categoryId] = state;
}

Future<void> loadCategoryItems(WidgetRef ref, String categoryId, {int pageSize = 20}) async {
  final service = ref.read(mediaServiceProvider);
  if (service == null) return;

  final currentState = _categoryItemsCache[categoryId] ?? CategoryItemsState();
  if (currentState.isLoading) return;

  _updateCategoryItems(categoryId, currentState.copyWith(isLoading: true, error: null));
  ref.invalidate(categoryItemsProvider(categoryId));

  final response = await service.getCategoryItems(categoryId, page: 1, pageSize: pageSize);

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
  ref.invalidate(categoryItemsProvider(categoryId));
}

Future<void> loadMoreCategoryItems(WidgetRef ref, String categoryId, {int pageSize = 20}) async {
  final service = ref.read(mediaServiceProvider);
  if (service == null) return;

  final currentState = _categoryItemsCache[categoryId] ?? CategoryItemsState();
  if (currentState.isLoading || !currentState.hasMore) return;

  _updateCategoryItems(categoryId, currentState.copyWith(isLoading: true));
  ref.invalidate(categoryItemsProvider(categoryId));

  final nextPage = currentState.currentPage + 1;
  final response = await service.getCategoryItems(categoryId, page: nextPage, pageSize: pageSize);

  if (response.isSuccess && response.data != null) {
    _updateCategoryItems(categoryId, CategoryItemsState(
      items: [...currentState.items, ...response.data!],
      isLoading: false,
      currentPage: nextPage,
      hasMore: response.data!.length >= pageSize,
    ));
  } else {
    _updateCategoryItems(categoryId, currentState.copyWith(isLoading: false, error: response.error));
  }
  ref.invalidate(categoryItemsProvider(categoryId));
}

Future<void> refreshCategoryItems(WidgetRef ref, String categoryId, {int pageSize = 20}) async {
  _categoryItemsCache.remove(categoryId);
  ref.invalidate(categoryItemsProvider(categoryId));
  await loadCategoryItems(ref, categoryId, pageSize: pageSize);
}
