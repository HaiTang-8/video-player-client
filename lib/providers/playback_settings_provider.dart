import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/app_constants.dart';
import '../data/models/playback_settings.dart';
import '../playback/cache/playback_cache_catalog.dart';
import '../playback/domain/engine_preference.dart';
import '../playback/playback_providers.dart';
import 'server_provider.dart';

final playbackSettingsProvider =
    NotifierProvider<PlaybackSettingsNotifier, PlaybackSettings>(
      PlaybackSettingsNotifier.new,
    );

class PlaybackSettingsNotifier extends Notifier<PlaybackSettings> {
  @override
  PlaybackSettings build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return PlaybackSettings(
      seekDuration: prefs.getInt(AppConstants.seekDurationKey) ?? 10,
      playbackSpeed: prefs.getDouble(AppConstants.playbackSpeedKey) ?? 1.0,
      longPressSpeed: prefs.getDouble(AppConstants.longPressSpeedKey) ?? 2.0,
      enginePreference:
          EnginePreference.values.asNameMap()[prefs.getString(
            AppConstants.enginePreferenceKey,
          )] ??
          EnginePreference.auto,
      cacheQuotaGb: _cacheQuotaGb(
        prefs.getInt(AppConstants.playbackCacheQuotaGbKey),
      ),
    );
  }

  static int _cacheQuotaGb(int? stored) =>
      stored != null && PlaybackCacheConfig.quotaOptionsGb.contains(stored)
          ? stored
          : PlaybackCacheConfig.defaultQuotaGb;

  Future<void> setSeekDuration(int duration) async {
    if (duration < 1 || duration > 60) return;
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setInt(AppConstants.seekDurationKey, duration);
    state = state.copyWith(seekDuration: duration);
  }

  Future<void> setPlaybackSpeed(double speed) async {
    if (speed < 0.25 || speed > 3.0) return;
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setDouble(AppConstants.playbackSpeedKey, speed);
    state = state.copyWith(playbackSpeed: speed);
  }

  Future<void> setLongPressSpeed(double speed) async {
    if (speed < 0.25 || speed > 3.0) return;
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setDouble(AppConstants.longPressSpeedKey, speed);
    state = state.copyWith(longPressSpeed: speed);
  }

  Future<void> setEnginePreference(EnginePreference preference) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(AppConstants.enginePreferenceKey, preference.name);
    state = state.copyWith(enginePreference: preference);
  }

  /// 立即按新上限淘汰；关闭（0）时清空已有缓存，之后播放直连
  Future<void> setCacheQuotaGb(int gb) async {
    if (!PlaybackCacheConfig.quotaOptionsGb.contains(gb)) return;
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setInt(AppConstants.playbackCacheQuotaGbKey, gb);
    state = state.copyWith(cacheQuotaGb: gb);
    if (ref.read(playbackCacheSupportedProvider)) {
      await ref.read(playbackCacheCatalogProvider).setQuota(gb << 30);
    }
  }
}
