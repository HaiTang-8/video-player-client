import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants/app_constants.dart';
import 'server_provider.dart';

@immutable
class DownloadSettings {
  final bool multiThreadEnabled;
  final int threadCount;

  const DownloadSettings({
    this.multiThreadEnabled = true,
    this.threadCount = 8,
  });

  DownloadSettings copyWith({bool? multiThreadEnabled, int? threadCount}) {
    return DownloadSettings(
      multiThreadEnabled: multiThreadEnabled ?? this.multiThreadEnabled,
      threadCount: threadCount ?? this.threadCount,
    );
  }
}

final downloadSettingsProvider =
    StateNotifierProvider<DownloadSettingsNotifier, DownloadSettings>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return DownloadSettingsNotifier(prefs);
});

class DownloadSettingsNotifier extends StateNotifier<DownloadSettings> {
  final SharedPreferences _prefs;

  DownloadSettingsNotifier(this._prefs) : super(_loadSettings(_prefs));

  static DownloadSettings _loadSettings(SharedPreferences prefs) {
    return DownloadSettings(
      multiThreadEnabled: prefs.getBool(AppConstants.downloadMultiThreadEnabledKey) ?? true,
      threadCount: prefs.getInt(AppConstants.downloadThreadCountKey) ?? 8,
    );
  }

  Future<void> setMultiThreadEnabled(bool enabled) async {
    await _prefs.setBool(AppConstants.downloadMultiThreadEnabledKey, enabled);
    state = state.copyWith(multiThreadEnabled: enabled);
  }

  Future<void> setThreadCount(int count) async {
    if (count < 1 || count > 32) return;
    await _prefs.setInt(AppConstants.downloadThreadCountKey, count);
    state = state.copyWith(threadCount: count);
  }
}
