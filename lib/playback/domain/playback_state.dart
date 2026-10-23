import 'media_track.dart';
import 'playback_error.dart';
import 'video_info.dart';

/// 引擎状态快照；音量 1.0 = 100%
class PlaybackSnapshot {
  final Duration position;
  final Duration duration;

  /// 不用再取数据就能播到的位置；内核不支持时为 0
  final Duration bufferedPosition;
  final bool playing;
  final bool buffering;
  final bool completed;

  /// 本次打开后第一帧画面已上屏（画面视图也已创建）；内核不支持时始终为 false
  final bool firstFrameRendered;

  /// 原生画面视图已挂载；不使用原生视图的内核始终为 false
  final bool videoViewAttached;
  final double rate;
  final double volume;
  final MediaTracks tracks;
  final SelectedTracks selectedTracks;
  final VideoInfo videoInfo;

  const PlaybackSnapshot({
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.bufferedPosition = Duration.zero,
    this.playing = false,
    this.buffering = false,
    this.completed = false,
    this.firstFrameRendered = false,
    this.videoViewAttached = false,
    this.rate = 1.0,
    this.volume = 1.0,
    this.tracks = const MediaTracks(),
    this.selectedTracks = const SelectedTracks(),
    this.videoInfo = const VideoInfo(),
  });
}

class PlaybackStreams {
  final Stream<Duration> position;
  final Stream<Duration> duration;
  final Stream<Duration> bufferedPosition;
  final Stream<bool> playing;
  final Stream<bool> buffering;
  final Stream<bool> completed;
  final Stream<bool> firstFrameRendered;
  final Stream<bool> videoViewAttached;
  final Stream<double> rate;
  final Stream<double> volume;
  final Stream<MediaTracks> tracks;
  final Stream<SelectedTracks> selectedTracks;
  final Stream<VideoInfo> videoInfo;
  final Stream<PlaybackError> errors;

  const PlaybackStreams({
    required this.position,
    required this.duration,
    required this.bufferedPosition,
    required this.playing,
    required this.buffering,
    required this.completed,
    required this.firstFrameRendered,
    required this.videoViewAttached,
    required this.rate,
    required this.volume,
    required this.tracks,
    required this.selectedTracks,
    required this.videoInfo,
    required this.errors,
  });
}
