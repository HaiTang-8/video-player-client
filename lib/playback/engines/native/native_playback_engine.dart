import 'package:flutter/widgets.dart';
import 'package:native_player/native_player.dart';

import '../../domain/playback_domain.dart';

/// 基于 Pigeon 契约的原生引擎（AetherEngine / Media3 共用）。
/// 必须先 [initialize] 拿到原生 playerId，之后才能调用其它方法
class NativePlaybackEngine
    implements PlaybackEngine, MediaDiagnosticsProvider, NativePlayerEventsApi {
  NativePlaybackEngine({
    required this.kind,
    required EngineCapabilities initialCapabilities,
    this.subtitleFontAssets = const [],
    NativePlayerHostApi? api,
    NativePlayerEventRegistry? events,
  }) : _capabilities = initialCapabilities,
       _api = api ?? NativePlayerHostApi(),
       _events = events ?? NativePlayerEventDispatcher.instance;

  @override
  final PlaybackEngineKind kind;

  /// 字幕渲染字体（Flutter 资源名），第一个为默认字体
  final List<String> subtitleFontAssets;
  EngineCapabilities _capabilities;
  final NativePlayerHostApi _api;
  final NativePlayerEventRegistry _events;
  final PlaybackStateHub _hub = PlaybackStateHub();
  MediaTracks _tracks = const MediaTracks();
  int? _playerId;

  /// 原生首帧和画面视图都就绪才算上屏：原生侧在视图挂进窗口前就可能出首帧
  bool _nativeFirstFrame = false;
  bool _viewCreated = false;
  bool _disposed = false;

  @override
  EngineCapabilities get capabilities => _capabilities;

  @override
  PlaybackSnapshot get state => _hub.state;

  @override
  PlaybackStreams get streams => _hub.streams;

  int get _id {
    final id = _playerId;
    if (id == null) {
      throw StateError('NativePlaybackEngine used before initialize');
    }
    return id;
  }

  @override
  Future<void> initialize() async {
    final caps = await _api.capabilities();
    _capabilities = EngineCapabilities(
      dolbyVisionColor: caps.dolbyVisionColor,
      maxVolume: caps.maxVolume,
      maxRate: caps.maxRate,
      reportsVideoView: true,
      subtitleDelay: caps.subtitleDelay,
    );
    if (subtitleFontAssets.isNotEmpty) {
      await _api.configureSubtitleFonts(subtitleFontAssets);
    }
    final id = await _api.create();
    if (_disposed) {
      await _api.dispose(id);
      return;
    }
    _playerId = id;
    _events.register(id, this);
  }

  @override
  Future<void> open(
    PlaybackSource source, {
    bool autoPlay = true,
    Duration? startPosition,
  }) {
    _tracks = const MediaTracks();
    _nativeFirstFrame = false;
    _hub.resetForNewMedia();
    return _api.open(
      _id,
      NativeSource(
        url: source.url,
        httpHeaders: source.httpHeaders,
        isLocalFile: source.isLocalFile,
        startPositionMs: startPosition?.inMilliseconds,
      ),
      autoPlay,
    );
  }

  @override
  Future<void> play() => _api.play(_id);

  @override
  Future<void> pause() => _api.pause(_id);

  @override
  Future<void> playOrPause() => _api.playOrPause(_id);

  @override
  Future<void> seek(Duration position) =>
      _api.seek(_id, position.inMilliseconds);

  @override
  Future<void> setRate(double rate) => _api.setRate(_id, rate);

  @override
  Future<void> setVolume(double volume) => _api.setVolume(_id, volume);

  @override
  Future<void> selectAudioTrack(AudioTrackInfo track) =>
      _api.selectAudioTrack(_id, track.id);

  @override
  Future<void> selectSubtitleTrack(SubtitleTrackInfo? track) =>
      _api.selectSubtitleTrack(_id, track?.id);

  @override
  Future<void> addExternalSubtitle(ExternalSubtitle subtitle) =>
      switch (subtitle) {
        ExternalSubtitleData(:final text, :final title, :final formatHint) =>
          _api.addExternalSubtitle(_id, text, title, formatHint),
      };

  @override
  Future<void> setSubtitleStyle(SubtitleStyle style) => _api.setSubtitleStyle(
    _id,
    NativeSubtitleStyle(
      scale: style.scale,
      color: style.color,
      backgroundOpacity: style.backgroundOpacity,
      bottomMargin: style.bottomMargin,
    ),
  );

  @override
  Future<void> setSubtitleDelay(Duration delay) =>
      _api.setSubtitleDelay(_id, delay.inMilliseconds);

  @override
  Future<MediaDiagnostics> fetchDiagnostics() async {
    final id = _playerId;
    if (id == null) return const MediaDiagnostics();
    final info = await _api.diagnostics(id);
    final output = info.outputDynamicRange;
    return MediaDiagnostics(
      videoDecoder: info.videoDecoder,
      outputDynamicRange: output == null ? null : _dynamicRange(output),
      details: info.details,
    );
  }

  @override
  Widget buildVideoView(BuildContext context, {required BoxFit fit}) {
    final id = _playerId;
    if (id == null) return const SizedBox.expand();
    return NativeVideoView(
      key: ValueKey(id),
      playerId: id,
      fit: fit == BoxFit.cover ? NativeVideoFit.cover : NativeVideoFit.contain,
      onFitChanged: (value) => _api.setVideoFit(id, value),
      onCreated: () {
        _viewCreated = true;
        _hub.update(videoViewAttached: true);
        _publishFirstFrame();
      },
      onDisposed: () {
        _viewCreated = false;
        _hub.update(videoViewAttached: false);
      },
    );
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final id = _playerId;
    if (id != null) {
      _events.unregister(id);
      try {
        await _api.dispose(id);
      } catch (_) {}
    }
    await _hub.close();
  }

  @override
  void onPosition(int playerId, int positionMs) =>
      _hub.update(position: Duration(milliseconds: positionMs));

  @override
  void onDuration(int playerId, int durationMs) =>
      _hub.update(duration: Duration(milliseconds: durationMs));

  @override
  void onBufferedPosition(int playerId, int bufferedMs) =>
      _hub.update(bufferedPosition: Duration(milliseconds: bufferedMs));

  @override
  void onPlaying(int playerId, bool playing) => _hub.update(playing: playing);

  @override
  void onFirstFrame(int playerId) {
    _nativeFirstFrame = true;
    _publishFirstFrame();
  }

  void _publishFirstFrame() {
    if (_nativeFirstFrame && _viewCreated) {
      _hub.update(firstFrameRendered: true);
    }
  }

  @override
  void onBuffering(int playerId, bool buffering) =>
      _hub.update(buffering: buffering);

  @override
  void onCompleted(int playerId, bool completed) =>
      _hub.update(completed: completed);

  @override
  void onRate(int playerId, double rate) => _hub.update(rate: rate);

  @override
  void onVolume(int playerId, double volume) => _hub.update(volume: volume);

  @override
  void onTracks(
    int playerId,
    List<NativeTrack> audio,
    List<NativeTrack> subtitle,
  ) {
    _tracks = MediaTracks(
      audio: [
        for (final t in audio)
          AudioTrackInfo(id: t.id, title: t.title, language: t.language),
      ],
      subtitle: [
        for (final t in subtitle)
          SubtitleTrackInfo(id: t.id, title: t.title, language: t.language),
      ],
    );
    _hub.update(tracks: _tracks);
  }

  @override
  void onSelectedTracks(
    int playerId,
    String? audioTrackId,
    String? subtitleTrackId,
    bool subtitleOff,
  ) => _hub.update(
    selectedTracks: SelectedTracks(
      audio:
          audioTrackId == null
              ? null
              : _tracks.audio.where((t) => t.id == audioTrackId).firstOrNull ??
                  AudioTrackInfo(id: audioTrackId),
      subtitle:
          subtitleTrackId == null
              ? null
              : _tracks.subtitle
                      .where((t) => t.id == subtitleTrackId)
                      .firstOrNull ??
                  SubtitleTrackInfo(id: subtitleTrackId),
      subtitleOff: subtitleOff,
    ),
  );

  @override
  void onVideoInfo(int playerId, NativeVideoInfo info) => _hub.update(
    videoInfo: VideoInfo(
      dynamicRange: _dynamicRange(info.dynamicRange),
      dolbyVisionProfile: info.dolbyVisionProfile,
    ),
  );

  static VideoDynamicRange _dynamicRange(NativeDynamicRange value) =>
      switch (value) {
        NativeDynamicRange.unknown => VideoDynamicRange.unknown,
        NativeDynamicRange.sdr => VideoDynamicRange.sdr,
        NativeDynamicRange.hdr10 => VideoDynamicRange.hdr10,
        NativeDynamicRange.hdr10Plus => VideoDynamicRange.hdr10Plus,
        NativeDynamicRange.hlg => VideoDynamicRange.hlg,
        NativeDynamicRange.dolbyVision => VideoDynamicRange.dolbyVision,
      };

  @override
  void onError(int playerId, NativeError error) => _hub.addError(
    PlaybackError(
      kind: switch (error.kind) {
        NativeErrorKind.network => PlaybackErrorKind.network,
        NativeErrorKind.http => PlaybackErrorKind.http,
        NativeErrorKind.audioOutput => PlaybackErrorKind.audioOutput,
        NativeErrorKind.source => PlaybackErrorKind.source,
        NativeErrorKind.decoder => PlaybackErrorKind.decoder,
        NativeErrorKind.unknown => PlaybackErrorKind.unknown,
      },
      message: error.message,
      httpStatus: error.httpStatus,
      recoverable: error.recoverable,
      fallbackSuggested: error.fallbackSuggested,
    ),
  );
}
