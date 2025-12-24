import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants/app_constants.dart';
import '../data/models/playback_settings.dart';
import 'server_provider.dart';

final playbackSettingsProvider =
    StateNotifierProvider<PlaybackSettingsNotifier, PlaybackSettings>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return PlaybackSettingsNotifier(prefs);
});

class PlaybackSettingsNotifier extends StateNotifier<PlaybackSettings> {
  final SharedPreferences _prefs;

  PlaybackSettingsNotifier(this._prefs) : super(_loadSettings(_prefs));

  static PlaybackSettings _loadSettings(SharedPreferences prefs) {
    return PlaybackSettings(
      seekDuration: prefs.getInt(AppConstants.seekDurationKey) ?? 10,
      playbackSpeed: prefs.getDouble(AppConstants.playbackSpeedKey) ?? 1.0,
    );
  }

  Future<void> setSeekDuration(int duration) async {
    if (duration < 1 || duration > 60) return;
    await _prefs.setInt(AppConstants.seekDurationKey, duration);
    state = state.copyWith(seekDuration: duration);
  }

  Future<void> setPlaybackSpeed(double speed) async {
    if (speed < 0.25 || speed > 3.0) return;
    await _prefs.setDouble(AppConstants.playbackSpeedKey, speed);
    state = state.copyWith(playbackSpeed: speed);
  }
}
