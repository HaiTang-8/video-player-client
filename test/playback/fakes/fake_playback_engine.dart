import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:media_player/playback/domain/playback_domain.dart';

/// 记录调用、由测试驱动状态的引擎替身
class FakePlaybackEngine implements PlaybackEngine {
  final PlaybackStateHub hub = PlaybackStateHub();
  final List<String> calls = [];
  PlaybackSource? openedSource;
  Object? openError;

  /// 设置后 seek 会等待它完成，用于模拟慢 seek
  Completer<void>? seekGate;
  bool disposed = false;

  @override
  PlaybackEngineKind get kind => PlaybackEngineKind.mpvTexture;

  @override
  EngineCapabilities get capabilities =>
      const EngineCapabilities(dolbyVisionColor: false, maxVolume: 2.0);

  @override
  PlaybackSnapshot get state => hub.state;

  @override
  PlaybackStreams get streams => hub.streams;

  @override
  Future<void> initialize() async => calls.add('initialize');

  @override
  Future<void> open(PlaybackSource source, {bool autoPlay = true}) async {
    calls.add('open ${source.url}');
    openedSource = source;
    final error = openError;
    if (error != null) throw error;
    hub.resetForNewMedia();
  }

  @override
  Future<void> play() async => calls.add('play');

  @override
  Future<void> pause() async => calls.add('pause');

  @override
  Future<void> playOrPause() async => calls.add('playOrPause');

  @override
  Future<void> seek(Duration position) async {
    calls.add('seek ${position.inSeconds}');
    final gate = seekGate;
    if (gate != null) await gate.future;
    hub.update(position: position);
  }

  @override
  Future<void> setRate(double rate) async {
    calls.add('rate $rate');
    hub.update(rate: rate);
  }

  @override
  Future<void> setVolume(double volume) async {
    calls.add('volume $volume');
    hub.update(volume: volume);
  }

  @override
  Future<void> selectAudioTrack(AudioTrackInfo track) async =>
      calls.add('audio ${track.id}');

  @override
  Future<void> selectSubtitleTrack(SubtitleTrackInfo? track) async =>
      calls.add('subtitle ${track?.id}');

  @override
  Future<void> addExternalSubtitle(ExternalSubtitle subtitle) async =>
      calls.add('external ${(subtitle as ExternalSubtitleData).title}');

  @override
  Widget buildVideoView(BuildContext context, {required BoxFit fit}) =>
      const SizedBox();

  @override
  Future<void> dispose() async {
    disposed = true;
    await hub.close();
  }
}
