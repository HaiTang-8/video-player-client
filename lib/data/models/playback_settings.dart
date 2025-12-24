import 'package:flutter/foundation.dart';

@immutable
class PlaybackSettings {
  final int seekDuration;
  final double playbackSpeed;

  const PlaybackSettings({
    this.seekDuration = 10,
    this.playbackSpeed = 1.0,
  });

  PlaybackSettings copyWith({
    int? seekDuration,
    double? playbackSpeed,
  }) {
    return PlaybackSettings(
      seekDuration: seekDuration ?? this.seekDuration,
      playbackSpeed: playbackSpeed ?? this.playbackSpeed,
    );
  }
}
