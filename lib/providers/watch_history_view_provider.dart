import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/app_constants.dart';
import 'server_provider.dart';

/// 观看历史展示模式：true 为合并，false 为不合并
final watchHistoryMergeEnabledProvider =
    NotifierProvider<WatchHistoryMergeEnabledNotifier, bool>(
        WatchHistoryMergeEnabledNotifier.new);

class WatchHistoryMergeEnabledNotifier extends Notifier<bool> {
  @override
  bool build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return prefs.getBool(AppConstants.watchHistoryMergeEnabledKey) ?? true;
  }

  Future<void> toggle() async {
    final prefs = ref.read(sharedPreferencesProvider);
    final newValue = !state;
    await prefs.setBool(AppConstants.watchHistoryMergeEnabledKey, newValue);
    state = newValue;
  }

  Future<void> setEnabled(bool enabled) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setBool(AppConstants.watchHistoryMergeEnabledKey, enabled);
    state = enabled;
  }
}

