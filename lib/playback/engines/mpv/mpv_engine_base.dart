import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import '../../domain/playback_domain.dart';
import 'mpv_diagnostics.dart';
import 'mpv_error_mapper.dart';
import 'mpv_options.dart';
import 'mpv_track_mapper.dart';
import 'speed_frame_limiter.dart';

/// mpv 系列引擎的公共实现；子类只负责视频输出（纹理 / 原生窗口）
abstract class MpvEngineBase
    implements
        PlaybackEngine,
        MediaDiagnosticsProvider,
        NetworkThroughputProvider {
  MpvEngineBase()
    : player = Player(
        configuration: const PlayerConfiguration(bufferSize: 256 * 1024 * 1024),
      ) {
    _speedFrameLimiter = SpeedFrameLimiter(player);
    _bindPlayerStreams();
  }

  @protected
  final Player player;
  final PlaybackStateHub _hub = PlaybackStateHub();
  final List<StreamSubscription> _subscriptions = [];
  late final SpeedFrameLimiter _speedFrameLimiter;
  bool _disposed = false;

  @override
  EngineCapabilities get capabilities =>
      const EngineCapabilities(dolbyVisionColor: false, maxVolume: 2.0);

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
  Future<void> open(PlaybackSource source, {bool autoPlay = true}) {
    _hub.resetForNewMedia();
    final media =
        source.isLocalFile
            ? Media(source.url)
            : Media(source.url, httpHeaders: source.httpHeaders);
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
  Future<Map<String, String>> fetchDiagnostics() async {
    final platform = player.platform;
    if (platform is! NativePlayer) return const {};
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
        s.error.listen((v) {
          final error = MpvErrorMapper.map(v);
          if (error != null) _hub.addError(error);
        }),
      );
  }
}
