import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/app_constants.dart';
import 'server_provider.dart';

final smoothScrollEnabledProvider =
    NotifierProvider<SmoothScrollNotifier, bool>(SmoothScrollNotifier.new);

class SmoothScrollNotifier extends Notifier<bool> {
  @override
  bool build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return prefs.getBool(AppConstants.smoothScrollEnabledKey) ?? true;
  }

  Future<void> toggle() async {
    final prefs = ref.read(sharedPreferencesProvider);
    final newValue = !state;
    await prefs.setBool(AppConstants.smoothScrollEnabledKey, newValue);
    state = newValue;
  }
}
