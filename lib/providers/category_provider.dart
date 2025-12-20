import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/models.dart';
import '../data/services/media_service.dart';
import 'media_provider.dart';

/// 分类统计状态
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

/// 分类统计 Provider
final categoriesProvider =
    StateNotifierProvider<CategoriesNotifier, CategoriesState>((ref) {
  final service = ref.watch(mediaServiceProvider);
  return CategoriesNotifier(service);
});

class CategoriesNotifier extends StateNotifier<CategoriesState> {
  final MediaService? _service;

  CategoriesNotifier(this._service) : super(CategoriesState());

  /// 加载分类统计
  Future<void> load() async {
    if (_service == null) return;
    if (state.isLoading) return;

    state = state.copyWith(isLoading: true, error: null);

    final response = await _service.getCategories();

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

  /// 刷新
  Future<void> refresh() async {
    state = CategoriesState();
    await load();
  }
}

/// 单个分类的内容状态
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

/// 分类内容 Provider（按分类 ID 获取）
final categoryItemsProvider = StateNotifierProvider.family<
    CategoryItemsNotifier, CategoryItemsState, String>((ref, categoryId) {
  final service = ref.watch(mediaServiceProvider);
  return CategoryItemsNotifier(service, categoryId);
});

class CategoryItemsNotifier extends StateNotifier<CategoryItemsState> {
  final MediaService? _service;
  final String categoryId;

  CategoryItemsNotifier(this._service, this.categoryId)
      : super(CategoryItemsState());

  /// 加载分类内容
  Future<void> load({int pageSize = 20}) async {
    if (_service == null) return;
    if (state.isLoading) return;

    state = state.copyWith(isLoading: true, error: null);

    final response = await _service.getCategoryItems(
      categoryId,
      page: 1,
      pageSize: pageSize,
    );

    if (response.isSuccess && response.data != null) {
      state = state.copyWith(
        items: response.data!,
        isLoading: false,
        currentPage: 1,
        hasMore: response.data!.length >= pageSize,
      );
    } else {
      state = state.copyWith(
        isLoading: false,
        error: response.error,
      );
    }
  }

  /// 加载更多
  Future<void> loadMore({int pageSize = 20}) async {
    if (_service == null) return;
    if (state.isLoading || !state.hasMore) return;

    state = state.copyWith(isLoading: true);

    final nextPage = state.currentPage + 1;
    final response = await _service.getCategoryItems(
      categoryId,
      page: nextPage,
      pageSize: pageSize,
    );

    if (response.isSuccess && response.data != null) {
      state = state.copyWith(
        items: [...state.items, ...response.data!],
        isLoading: false,
        currentPage: nextPage,
        hasMore: response.data!.length >= pageSize,
      );
    } else {
      state = state.copyWith(
        isLoading: false,
        error: response.error,
      );
    }
  }

  /// 刷新
  Future<void> refresh({int pageSize = 20}) async {
    state = CategoryItemsState();
    await load(pageSize: pageSize);
  }
}
