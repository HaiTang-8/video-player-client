import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/models.dart';
import 'media_provider.dart';

class WatchHistoryState {
  final List<WatchHistoryItem> items;
  final bool isLoading;
  final String? error;

  WatchHistoryState({
    this.items = const [],
    this.isLoading = false,
    this.error,
  });

  WatchHistoryState copyWith({
    List<WatchHistoryItem>? items,
    bool? isLoading,
    String? error,
  }) {
    return WatchHistoryState(
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

final watchHistoryProvider = NotifierProvider<WatchHistoryNotifier, WatchHistoryState>(WatchHistoryNotifier.new);

class WatchHistoryNotifier extends Notifier<WatchHistoryState> {
  @override
  WatchHistoryState build() => WatchHistoryState();

  Future<void> load({int limit = 20}) async {
    final service = ref.read(mediaServiceProvider);
    if (service == null) return;
    if (state.isLoading) return;

    state = state.copyWith(isLoading: true, error: null);

    final response = await service.getRecentlyWatched(limit: limit);

    if (response.isSuccess && response.data != null) {
      state = state.copyWith(
        items: response.data!,
        isLoading: false,
      );
    } else {
      state = state.copyWith(
        isLoading: false,
        error: response.error,
      );
    }
  }

  Future<void> refresh({int limit = 20}) async {
    final service = ref.read(mediaServiceProvider);
    if (service == null) return;
    if (state.isLoading) return;

    final response = await service.getRecentlyWatched(limit: limit);

    if (response.isSuccess && response.data != null) {
      state = state.copyWith(items: response.data!);
    }
  }

  Future<bool> delete(int id) async {
    final service = ref.read(mediaServiceProvider);
    if (service == null) return false;

    final response = await service.deleteWatchHistory(id);
    if (response.isSuccess) {
      state = state.copyWith(
        items: state.items.where((item) => item.id != id).toList(),
      );
      return true;
    }
    return false;
  }

  Future<bool> deleteBatch(List<int> ids) async {
    final service = ref.read(mediaServiceProvider);
    if (service == null) return false;

    final response = await service.deleteWatchHistoryBatch(ids);
    if (response.isSuccess) {
      state = state.copyWith(
        items: state.items.where((item) => !ids.contains(item.id)).toList(),
      );
      return true;
    }
    return false;
  }

  Future<bool> deleteAll() async {
    final service = ref.read(mediaServiceProvider);
    if (service == null) return false;

    final response = await service.deleteAllWatchHistory();
    if (response.isSuccess) {
      state = state.copyWith(items: []);
      return true;
    }
    return false;
  }
}

/// 观看历史分组扩展：将原始记录合并为“剧集卡片”
extension WatchHistoryStateGrouping on WatchHistoryState {
  /// 按剧集媒体合并后的列表（用于 UI 展示）
  List<WatchHistoryGroup> groupedItems({bool mergeEpisodes = true}) {
    // 这里集中处理合并逻辑，避免各页面重复实现
    return WatchHistoryGroup.groupItems(
      items,
      mergeEpisodes: mergeEpisodes,
    );
  }
}
