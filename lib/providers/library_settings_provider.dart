import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/app_constants.dart';
import 'server_provider.dart';

@immutable
class LibrarySettings {
  final int desktopRowCount;

  const LibrarySettings({this.desktopRowCount = 1});

  LibrarySettings copyWith({int? desktopRowCount}) {
    return LibrarySettings(
      desktopRowCount: desktopRowCount ?? this.desktopRowCount,
    );
  }
}

final librarySettingsProvider =
    NotifierProvider<LibrarySettingsNotifier, LibrarySettings>(
      LibrarySettingsNotifier.new,
    );

class LibrarySettingsNotifier extends Notifier<LibrarySettings> {
  @override
  LibrarySettings build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final rowCount = prefs.getInt(AppConstants.libraryDesktopRowCountKey) ?? 1;
    return LibrarySettings(desktopRowCount: rowCount.clamp(1, 3));
  }

  Future<void> setDesktopRowCount(int count) async {
    if (count < 1 || count > 3) return;
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setInt(AppConstants.libraryDesktopRowCountKey, count);
    state = state.copyWith(desktopRowCount: count);
  }
}
