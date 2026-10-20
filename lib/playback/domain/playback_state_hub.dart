import 'dart:async';

import 'media_track.dart';
import 'playback_error.dart';
import 'playback_state.dart';
import 'video_info.dart';

/// 引擎共用的状态发布器：维护最新快照，值变化时才广播
class PlaybackStateHub {
  final _position = StreamController<Duration>.broadcast();
  final _duration = StreamController<Duration>.broadcast();
  final _playing = StreamController<bool>.broadcast();
  final _buffering = StreamController<bool>.broadcast();
  final _completed = StreamController<bool>.broadcast();
  final _rate = StreamController<double>.broadcast();
  final _volume = StreamController<double>.broadcast();
  final _tracks = StreamController<MediaTracks>.broadcast();
  final _selectedTracks = StreamController<SelectedTracks>.broadcast();
  final _videoInfo = StreamController<VideoInfo>.broadcast();
  final _errors = StreamController<PlaybackError>.broadcast();

  PlaybackSnapshot _state = const PlaybackSnapshot();
  bool _closed = false;

  late final PlaybackStreams streams = PlaybackStreams(
    position: _position.stream,
    duration: _duration.stream,
    playing: _playing.stream,
    buffering: _buffering.stream,
    completed: _completed.stream,
    rate: _rate.stream,
    volume: _volume.stream,
    tracks: _tracks.stream,
    selectedTracks: _selectedTracks.stream,
    videoInfo: _videoInfo.stream,
    errors: _errors.stream,
  );

  PlaybackSnapshot get state => _state;

  void update({
    Duration? position,
    Duration? duration,
    bool? playing,
    bool? buffering,
    bool? completed,
    double? rate,
    double? volume,
    MediaTracks? tracks,
    SelectedTracks? selectedTracks,
    VideoInfo? videoInfo,
  }) {
    if (_closed) return;
    final s = _state;
    _state = PlaybackSnapshot(
      position: _apply(position, s.position, _position),
      duration: _apply(duration, s.duration, _duration),
      playing: _apply(playing, s.playing, _playing),
      buffering: _apply(buffering, s.buffering, _buffering),
      completed: _apply(completed, s.completed, _completed),
      rate: _apply(rate, s.rate, _rate),
      volume: _apply(volume, s.volume, _volume),
      tracks: _apply(tracks, s.tracks, _tracks),
      selectedTracks: _apply(selectedTracks, s.selectedTracks, _selectedTracks),
      videoInfo: _apply(videoInfo, s.videoInfo, _videoInfo),
    );
  }

  /// 打开新媒体前调用，清掉属于上一个媒体的状态，保证新媒体的同值事件仍会广播。
  /// 选中的轨道不重置：mpv 的轨道选择（如关闭字幕）会延续到下一个文件
  void resetForNewMedia() => update(
    position: Duration.zero,
    duration: Duration.zero,
    completed: false,
    tracks: const MediaTracks(),
    videoInfo: const VideoInfo(),
  );

  void addError(PlaybackError error) {
    if (!_closed) _errors.add(error);
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await Future.wait([
      _position.close(),
      _duration.close(),
      _playing.close(),
      _buffering.close(),
      _completed.close(),
      _rate.close(),
      _volume.close(),
      _tracks.close(),
      _selectedTracks.close(),
      _videoInfo.close(),
      _errors.close(),
    ]);
  }

  T _apply<T>(T? next, T current, StreamController<T> controller) {
    if (next == null || next == current) return current;
    controller.add(next);
    return next;
  }
}
