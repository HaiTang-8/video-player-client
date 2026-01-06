import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

final downloadSettingsProvider = NotifierProvider<DownloadSettingsNotifier, DownloadSettings>(DownloadSettingsNotifier.new);

class DownloadSettingsNotifier extends Notifier<DownloadSettings> {
  @override
  DownloadSettings build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return DownloadSettings(
      multiThreadEnabled: prefs.getBool(AppConstants.downloadMultiThreadEnabledKey) ?? true,
      threadCount: prefs.getInt(AppConstants.downloadThreadCountKey) ?? 8,
    );
  }

  Future<void> setMultiThreadEnabled(bool enabled) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setBool(AppConstants.downloadMultiThreadEnabledKey, enabled);
    state = state.copyWith(multiThreadEnabled: enabled);
  }

  Future<void> setThreadCount(int count) async {
    if (count < 1 || count > 32) return;
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setInt(AppConstants.downloadThreadCountKey, count);
    state = state.copyWith(threadCount: count);
  }
}
