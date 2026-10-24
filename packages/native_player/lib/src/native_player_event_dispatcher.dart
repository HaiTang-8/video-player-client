import 'generated/native_player_api.g.dart';

abstract interface class NativePlayerEventRegistry {
  void register(int playerId, NativePlayerEventsApi listener);
  void unregister(int playerId);
}

/// 原生事件在 Dart 侧只能有一个接收者，由它按 playerId 分发给各引擎
class NativePlayerEventDispatcher
    implements NativePlayerEventsApi, NativePlayerEventRegistry {
  NativePlayerEventDispatcher._();

  static final NativePlayerEventDispatcher instance =
      NativePlayerEventDispatcher._();

  final Map<int, NativePlayerEventsApi> _listeners = {};
  bool _attached = false;

  @override
  void register(int playerId, NativePlayerEventsApi listener) {
    if (!_attached) {
      NativePlayerEventsApi.setUp(this);
      _attached = true;
    }
    _listeners[playerId] = listener;
  }

  @override
  void unregister(int playerId) => _listeners.remove(playerId);

  @override
  void onPosition(int playerId, int positionMs) =>
      _listeners[playerId]?.onPosition(playerId, positionMs);

  @override
  void onDuration(int playerId, int durationMs) =>
      _listeners[playerId]?.onDuration(playerId, durationMs);

  @override
  void onBufferedPosition(int playerId, int bufferedMs) =>
      _listeners[playerId]?.onBufferedPosition(playerId, bufferedMs);

  @override
  void onPlaying(int playerId, bool playing) =>
      _listeners[playerId]?.onPlaying(playerId, playing);

  @override
  void onBuffering(int playerId, bool buffering) =>
      _listeners[playerId]?.onBuffering(playerId, buffering);

  @override
  void onBufferingProgress(int playerId, double progress) =>
      _listeners[playerId]?.onBufferingProgress(playerId, progress);

  @override
  void onCompleted(int playerId, bool completed) =>
      _listeners[playerId]?.onCompleted(playerId, completed);

  @override
  void onFirstFrame(int playerId) => _listeners[playerId]?.onFirstFrame(playerId);

  @override
  void onRate(int playerId, double rate) =>
      _listeners[playerId]?.onRate(playerId, rate);

  @override
  void onVolume(int playerId, double volume) =>
      _listeners[playerId]?.onVolume(playerId, volume);

  @override
  void onTracks(
    int playerId,
    List<NativeTrack> audio,
    List<NativeTrack> subtitle,
  ) => _listeners[playerId]?.onTracks(playerId, audio, subtitle);

  @override
  void onSelectedTracks(
    int playerId,
    String? audioTrackId,
    String? subtitleTrackId,
    bool subtitleOff,
  ) => _listeners[playerId]?.onSelectedTracks(
    playerId,
    audioTrackId,
    subtitleTrackId,
    subtitleOff,
  );

  @override
  void onVideoInfo(int playerId, NativeVideoInfo info) =>
      _listeners[playerId]?.onVideoInfo(playerId, info);

  @override
  void onError(int playerId, NativeError error) =>
      _listeners[playerId]?.onError(playerId, error);
}
