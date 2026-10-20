import '../domain/playback_domain.dart';

typedef PlaybackEngineBuilder = PlaybackEngine Function();

/// 按内核类型创建引擎；新增内核只需注册一个构造器
class PlaybackEngineFactory {
  const PlaybackEngineFactory(this._builders);

  final Map<PlaybackEngineKind, PlaybackEngineBuilder> _builders;

  PlaybackEngine create(PlaybackEngineKind kind) {
    final builder = _builders[kind];
    if (builder == null) {
      throw UnsupportedError('Playback engine not registered: $kind');
    }
    return builder();
  }
}
