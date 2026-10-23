import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/app_constants.dart';
import '../playback/domain/subtitle_style.dart';
import 'server_provider.dart';

final subtitleSettingsProvider =
    NotifierProvider<SubtitleSettingsNotifier, SubtitleStyle>(
      SubtitleSettingsNotifier.new,
    );

class SubtitleSettingsNotifier extends Notifier<SubtitleStyle> {
  @override
  SubtitleStyle build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    const d = SubtitleStyle.defaults;
    return SubtitleStyle(
      scale: prefs.getDouble(AppConstants.subtitleScaleKey) ?? d.scale,
      color: prefs.getInt(AppConstants.subtitleColorKey) ?? d.color,
      backgroundOpacity:
          prefs.getDouble(AppConstants.subtitleBackgroundOpacityKey) ??
          d.backgroundOpacity,
      bottomMargin:
          prefs.getDouble(AppConstants.subtitleBottomMarginKey) ??
          d.bottomMargin,
    );
  }

  /// [persist] 为 false 时只更新内存（滑块拖动中），松手后再保存
  Future<void> update(SubtitleStyle style, {bool persist = true}) async {
    state = style;
    if (!persist) return;
    final prefs = ref.read(sharedPreferencesProvider);
    await Future.wait([
      prefs.setDouble(AppConstants.subtitleScaleKey, style.scale),
      prefs.setInt(AppConstants.subtitleColorKey, style.color),
      prefs.setDouble(
        AppConstants.subtitleBackgroundOpacityKey,
        style.backgroundOpacity,
      ),
      prefs.setDouble(AppConstants.subtitleBottomMarginKey, style.bottomMargin),
    ]);
  }

  Future<void> reset() => update(SubtitleStyle.defaults);
}
