import 'package:flutter/foundation.dart';

@immutable
class AudioTrackInfo {
  final String id;
  final String? title;
  final String? language;

  const AudioTrackInfo({required this.id, this.title, this.language});

  @override
  bool operator ==(Object other) =>
      other is AudioTrackInfo &&
      other.id == id &&
      other.title == title &&
      other.language == language;

  @override
  int get hashCode => Object.hash(id, title, language);
}

@immutable
class SubtitleTrackInfo {
  final String id;
  final String? title;
  final String? language;

  const SubtitleTrackInfo({required this.id, this.title, this.language});

  @override
  bool operator ==(Object other) =>
      other is SubtitleTrackInfo &&
      other.id == id &&
      other.title == title &&
      other.language == language;

  @override
  int get hashCode => Object.hash(id, title, language);
}

@immutable
class MediaTracks {
  final List<AudioTrackInfo> audio;
  final List<SubtitleTrackInfo> subtitle;

  const MediaTracks({this.audio = const [], this.subtitle = const []});

  @override
  bool operator ==(Object other) =>
      other is MediaTracks &&
      listEquals(other.audio, audio) &&
      listEquals(other.subtitle, subtitle);

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(audio), Object.hashAll(subtitle));
}

/// 当前选中的轨道；subtitle 为 null 表示字幕关闭
@immutable
class SelectedTracks {
  final AudioTrackInfo? audio;
  final SubtitleTrackInfo? subtitle;

  const SelectedTracks({this.audio, this.subtitle});

  @override
  bool operator ==(Object other) =>
      other is SelectedTracks &&
      other.audio == audio &&
      other.subtitle == subtitle;

  @override
  int get hashCode => Object.hash(audio, subtitle);
}
