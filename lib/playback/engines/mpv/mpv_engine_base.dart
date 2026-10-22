import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import '../../domain/playback_domain.dart';
import 'dolby_vision_log_detector.dart';
import 'mpv_diagnostics.dart';
import 'mpv_error_mapper.dart';
import 'mpv_options.dart';
import 'mpv_track_mapper.dart';
import 'mpv_video_info.dart';
import 'speed_frame_limiter.dart';

/// mpv 系列引擎的公共实现；子类只负责视频输出（纹理 / 原生窗口）
abstract class MpvEngineBase
    implements
        PlaybackEngine,
        MediaDiagnosticsProvider,
        NetworkThroughputProvider {
  MpvEngineBase()
    : player = Player(
        // verbose 日志用于识别杜比视界配置记录，正常播放时日志量很小
        configuration: const PlayerConfiguration(
          bufferSize: 256 * 1024 * 1024,
          logLevel: MPVLogLevel.v,
        ),
      ) {
    _speedFrameLimiter = SpeedFrameLimiter(player);
    _bindPlayerStreams();
  }

  @protected
  final Player player;
  final PlaybackStateHub _hub = PlaybackStateHub();
  final List<StreamSubscription> _subscriptions = [];
  late final SpeedFrameLimiter _speedFrameLimiter;
  final DolbyVisionLogDetector _dolbyVision = DolbyVisionLogDetector();
  int _mediaGeneration = 0;
  String? _gamma;
  int? _inferredDolbyVisionProfile;
  bool _profileInferenceStarted = false;
  bool _disposed = false;

  @override
  EngineCapabilities get capabilities => const EngineCapabilities(
    dolbyVisionColor: false,
    maxVolume: 2.0,
    maxRate: 100,
  );

  @override
  PlaybackSnapshot get state => _hub.state;

  @override
  PlaybackStreams get streams => _hub.streams;

  /// 子类可在此追加视频输出相关属性
  @protected
  MpvOptions buildOptions() => MpvOptions().networkResilience().streamCache();

  @override
  Future<void> initialize() async {
    final platform = player.platform;
    if (platform is! NativePlayer) return;
    for (final entry in buildOptions().build().entries) {
      await platform.setProperty(entry.key, entry.value);
    }
  }

  @override
  Future<void> open(
    PlaybackSource source, {
    bool autoPlay = true,
    Duration? startPosition,
  }) {
    _mediaGeneration++;
    _dolbyVision.reset();
    _gamma = null;
    _inferredDolbyVisionProfile = null;
    _profileInferenceStarted = false;
    _hub.resetForNewMedia();
    final media =
        source.isLocalFile
            ? Media(source.url, start: startPosition)
            : Media(
              source.url,
              httpHeaders: source.httpHeaders,
              start: startPosition,
            );
    return player.open(media, play: autoPlay);
  }

  @override
  Future<void> play() => player.play();

  @override
  Future<void> pause() => player.pause();

  @override
  Future<void> playOrPause() => player.playOrPause();

  @override
  Future<void> seek(Duration position) => player.seek(position);

  @override
  Future<void> setRate(double rate) => player.setRate(rate);

  @override
  Future<void> setVolume(double volume) => player.setVolume(volume * 100);

  @override
  Future<void> selectAudioTrack(AudioTrackInfo track) => player.setAudioTrack(
    MpvTrackMapper.toNativeAudio(track, player.state.tracks),
  );

  @override
  Future<void> selectSubtitleTrack(SubtitleTrackInfo? track) =>
      player.setSubtitleTrack(
        MpvTrackMapper.toNativeSubtitle(track, player.state.tracks),
      );

  @override
  Future<void> addExternalSubtitle(ExternalSubtitle subtitle) =>
      switch (subtitle) {
        ExternalSubtitleData(:final text, :final title) => player
            .setSubtitleTrack(SubtitleTrack.data(text, title: title)),
      };

  @override
  Future<MediaDiagnostics> fetchDiagnostics() async {
    final platform = player.platform;
    if (platform is! NativePlayer) return const MediaDiagnostics();
    return MpvDiagnostics.read(platform);
  }

  @override
  Future<double?> currentDownloadBytesPerSecond() async {
    final platform = player.platform;
    if (platform is! NativePlayer) return null;
    return MpvDiagnostics.cacheSpeed(platform);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    _speedFrameLimiter.dispose();
    await player.dispose();
    await _hub.close();
  }

  void _bindPlayerStreams() {
    final s = player.stream;
    _subscriptions
      ..add(s.position.listen((v) => _hub.update(position: v)))
      ..add(s.duration.listen((v) => _hub.update(duration: v)))
      ..add(s.playing.listen((v) => _hub.update(playing: v)))
      ..add(s.buffering.listen((v) => _hub.update(buffering: v)))
      ..add(s.completed.listen((v) => _hub.update(completed: v)))
      ..add(s.rate.listen((v) => _hub.update(rate: v)))
      ..add(s.volume.listen((v) => _hub.update(volume: v / 100)))
      ..add(
        s.tracks.listen((v) => _hub.update(tracks: MpvTrackMapper.tracks(v))),
      )
      ..add(
        s.track.listen(
          (v) => _hub.update(selectedTracks: MpvTrackMapper.selected(v)),
        ),
      )
      ..add(
        s.videoParams.listen((v) {
          _gamma = v.gamma;
          _publishVideoInfo();
        }),
      )
      ..add(
        s.log.listen((v) {
          if (_dolbyVision.onLog(v.prefix, v.text)) _publishVideoInfo();
        }),
      )
      ..add(
        s.error.listen((v) {
          final error = MpvErrorMapper.map(v);
          if (error != null) _hub.addError(error);
        }),
      );
  }

  void _publishVideoInfo() {
    if (_disposed) return;
    if (_dolbyVision.detected &&
        _dolbyVision.profile == null &&
        _gamma != null &&
        !_profileInferenceStarted) {
      _profileInferenceStarted = true;
      unawaited(_inferDolbyVisionProfile(_mediaGeneration));
    }
    _hub.update(
      videoInfo: MpvVideoInfo.resolve(
        gamma: _gamma,
        dolbyVision: _dolbyVision.detected,
        dolbyVisionProfile: _dolbyVision.profile ?? _inferredDolbyVisionProfile,
      ),
    );
  }

  /// 只有码流内 RPU 信号时，用解码器色彩参数推断是否为 Profile 5
  Future<void> _inferDolbyVisionProfile(int generation) async {
    final platform = player.platform;
    if (platform is! NativePlayer) return;
    try {
      final matrix = await platform.getProperty('video-dec-params/colormatrix');
      final gamma = await platform.getProperty('video-dec-params/gamma');
      if (_disposed || generation != _mediaGeneration) return;
      if (MpvVideoInfo.looksLikeProfile5(
        decoderColormatrix: matrix,
        decoderGamma: gamma,
      )) {
        _inferredDolbyVisionProfile = 5;
        _publishVideoInfo();
      }
    } catch (_) {}
  }
}
