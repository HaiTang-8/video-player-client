import 'package:flutter/foundation.dart';

import '../../playback/domain/engine_preference.dart';

@immutable
class PlaybackSettings {
  final int seekDuration;
  final double playbackSpeed;
  final double longPressSpeed;
  final EnginePreference enginePreference;

  const PlaybackSettings({
    this.seekDuration = 10,
    this.playbackSpeed = 1.0,
    this.longPressSpeed = 2.0,
    this.enginePreference = EnginePreference.auto,
  });

  PlaybackSettings copyWith({
    int? seekDuration,
    double? playbackSpeed,
    double? longPressSpeed,
    EnginePreference? enginePreference,
  }) {
    return PlaybackSettings(
      seekDuration: seekDuration ?? this.seekDuration,
      playbackSpeed: playbackSpeed ?? this.playbackSpeed,
      longPressSpeed: longPressSpeed ?? this.longPressSpeed,
      enginePreference: enginePreference ?? this.enginePreference,
    );
  }
}
