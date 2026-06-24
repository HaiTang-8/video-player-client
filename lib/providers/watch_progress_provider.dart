import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/models.dart';

typedef WatchProgressKey =
    ({String mediaType, int mediaId, int? episodeId, int? seasonId});

final watchProgressProvider = NotifierProvider<
  WatchProgressNotifier,
  Map<WatchProgressKey, WatchHistoryItem>
>(WatchProgressNotifier.new);

class WatchProgressNotifier
    extends Notifier<Map<WatchProgressKey, WatchHistoryItem>> {
  @override
  Map<WatchProgressKey, WatchHistoryItem> build() => const {};

  WatchHistoryItem? read(WatchProgressKey key) => state[key];

  void upsert(WatchProgressKey key, WatchHistoryItem item) {
    state = {...state, key: item};
  }

  void remove(WatchProgressKey key) {
    if (!state.containsKey(key)) return;
    final next = Map<WatchProgressKey, WatchHistoryItem>.from(state);
    next.remove(key);
    state = next;
  }

  void upsertFromPlayback({
    required String mediaType,
    required int mediaId,
    int? episodeId,
    int? seasonId,
    required int position,
    required int duration,
  }) {
    final completed = duration > 0 && position >= duration - 60;
    final item = WatchHistoryItem(
      id: 0,
      mediaType: mediaType,
      mediaId: mediaId,
      episodeId: episodeId,
      position: position,
      duration: duration,
      completed: completed,
      watchedAt: DateTime.now(),
    );
    final mediaKey = (
      mediaType: mediaType,
      mediaId: mediaId,
      episodeId: episodeId,
      seasonId: seasonId,
    );
    if (completed) {
      remove(mediaKey);
    } else {
      upsert(mediaKey, item);
    }

    if (mediaType == 'tv' && seasonId != null) {
      final seasonKey = (
        mediaType: mediaType,
        mediaId: mediaId,
        episodeId: null,
        seasonId: seasonId,
      );
      if (completed) {
        remove(seasonKey);
      } else {
        upsert(seasonKey, item);
      }
    }
  }
}
