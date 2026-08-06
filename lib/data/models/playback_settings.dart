import 'package:flutter/foundation.dart';

@immutable
class PlaybackSettings {
  final int seekDuration;
  final double playbackSpeed;
  final double longPressSpeed;

  const PlaybackSettings({
    this.seekDuration = 10,
    this.playbackSpeed = 1.0,
    this.longPressSpeed = 2.0,
  });

  PlaybackSettings copyWith({
    int? seekDuration,
    double? playbackSpeed,
    double? longPressSpeed,
  }) {
    return PlaybackSettings(
      seekDuration: seekDuration ?? this.seekDuration,
      playbackSpeed: playbackSpeed ?? this.playbackSpeed,
      longPressSpeed: longPressSpeed ?? this.longPressSpeed,
    );
  }
}
