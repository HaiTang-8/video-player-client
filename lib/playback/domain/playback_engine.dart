import 'package:flutter/widgets.dart';

import 'engine_capabilities.dart';
import 'media_track.dart';
import 'playback_engine_kind.dart';
import 'playback_source.dart';
import 'playback_state.dart';
import 'video_info.dart';

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

/// 媒体信息面板数据：通用项由面板统一排版，[details] 为内核专属项（键为展示名，按插入顺序展示）
class MediaDiagnostics {
  final String? videoDecoder;

  /// 实际送显的动态范围，SDR 表示 HDR 片源已被映射为 SDR；未知时为 null
  final VideoDynamicRange? outputDynamicRange;

  final Map<String, String> details;

  const MediaDiagnostics({
    this.videoDecoder,
    this.outputDynamicRange,
    this.details = const {},
  });
}

abstract interface class MediaDiagnosticsProvider {
  Future<MediaDiagnostics> fetchDiagnostics();
}

abstract interface class NetworkThroughputProvider {
  /// 当前下载速度（字节/秒），未知时为 null
  Future<double?> currentDownloadBytesPerSecond();
}
