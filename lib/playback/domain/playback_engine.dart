import 'package:flutter/widgets.dart';

import 'engine_capabilities.dart';
import 'media_track.dart';
import 'playback_engine_kind.dart';
import 'playback_source.dart';
import 'playback_state.dart';

/// 播放内核统一接口。音量 1.0 = 100%，上限见 [EngineCapabilities.maxVolume]
abstract interface class PlaybackEngine {
  PlaybackEngineKind get kind;
  EngineCapabilities get capabilities;
  PlaybackSnapshot get state;
  PlaybackStreams get streams;

  Future<void> initialize();
  Future<void> open(PlaybackSource source, {bool autoPlay = true});
  Future<void> play();
  Future<void> pause();
  Future<void> playOrPause();
  Future<void> seek(Duration position);
  Future<void> setRate(double rate);
  Future<void> setVolume(double volume);
  Future<void> selectAudioTrack(AudioTrackInfo track);

  /// [track] 为 null 时关闭字幕
  Future<void> selectSubtitleTrack(SubtitleTrackInfo? track);

  /// 加载并选中外挂字幕
  Future<void> addExternalSubtitle(ExternalSubtitle subtitle);

  Widget buildVideoView(BuildContext context, {required BoxFit fit});

  /// 幂等；之后不再发出任何事件
  Future<void> dispose();
}

/// 媒体信息面板数据，键为展示名，按插入顺序展示
abstract interface class MediaDiagnosticsProvider {
  Future<Map<String, String>> fetchDiagnostics();
}

abstract interface class NetworkThroughputProvider {
  /// 当前下载速度（字节/秒），未知时为 null
  Future<double?> currentDownloadBytesPerSecond();
}
