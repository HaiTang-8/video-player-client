import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/models.dart';
import '../data/services/media_service.dart';
import 'media_provider.dart';

/// 最近观看状态
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

/// 最近观看 Provider
final watchHistoryProvider =
    StateNotifierProvider<WatchHistoryNotifier, WatchHistoryState>((ref) {
  final service = ref.watch(mediaServiceProvider);
  return WatchHistoryNotifier(service);
});

class WatchHistoryNotifier extends StateNotifier<WatchHistoryState> {
  final MediaService? _service;

  WatchHistoryNotifier(this._service) : super(WatchHistoryState());

  Future<void> load({int limit = 20}) async {
    if (_service == null) return;
    if (state.isLoading) return;

    state = state.copyWith(isLoading: true, error: null);

    final response = await _service.getRecentlyWatched(limit: limit);

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
    if (_service == null) return;
    if (state.isLoading) return;

    final response = await _service.getRecentlyWatched(limit: limit);

    if (response.isSuccess && response.data != null) {
      state = state.copyWith(items: response.data!);
    }
  }
}
