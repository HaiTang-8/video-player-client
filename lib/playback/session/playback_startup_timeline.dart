import '../domain/playback_domain.dart';

/// 一次加载的起播耗时，各阶段为相对 load 开始的时间；未经历的阶段为 null
final class PlaybackStartupReport {
  const PlaybackStartupReport({
    required this.engine,
    required this.localFile,
    required this.target,
    required this.resolved,
    required this.opened,
    required this.firstPlaying,
    required this.firstFrame,
    required this.ready,
    this.viewAttached,
  });

  final PlaybackEngineKind engine;
  final bool localFile;
  final Duration? target;
  final Duration? resolved;
  final Duration? opened;
  final Duration? firstPlaying;

  /// 第一帧画面上屏；内核不支持首帧事件时为 null
  final Duration? firstFrame;

  /// 原生画面视图挂载；不使用原生视图的内核为 null
  final Duration? viewAttached;

  /// 在起播位置（没有起播位置时为开头）不缓冲地播放了 300ms
  final Duration ready;

  @override
  String toString() =>
      'engine=${engine.name} source=${localFile ? 'file' : 'network'} '
      'target=${target?.inSeconds ?? 0}s resolve=${_ms(resolved)} '
      'open=${_ms(opened)} view=${_ms(viewAttached)} '
      'playing=${_ms(firstPlaying)} firstFrame=${_ms(firstFrame)} '
      'ready=${_ms(ready)}';

  static String _ms(Duration? d) => d == null ? '-' : '${d.inMilliseconds}ms';
}

/// 记录从 load 开始到在起播位置开始播放的各阶段耗时
class PlaybackStartupTimeline {
  PlaybackStartupTimeline({required this.engine, this.target});

  /// 内核 seek 后可能落在目标之前的关键帧
  static const _targetTolerance = Duration(seconds: 1);

  /// seek 后内核会立即报告目标位置，位置继续前进才算真正开始播放
  static const _minProgress = Duration(milliseconds: 300);

  final PlaybackEngineKind engine;
  final Duration? target;
  final Stopwatch _watch = Stopwatch()..start();
  bool _localFile = false;
  Duration? _resolved;
  Duration? _opened;
  Duration? _firstPlaying;
  Duration? _firstFrame;
  Duration? _viewAttached;
  Duration? _anchor;

  void markResolved({required bool localFile}) {
    _localFile = localFile;
    _resolved = _watch.elapsed;
  }

  void markOpened() => _opened = _watch.elapsed;

  /// 到达起播位置时返回报告，之后不再需要调用
  PlaybackStartupReport? onState(PlaybackSnapshot state) {
    // 解析完成前快照里还是上一个媒体的状态；解析后会同步调用 open 重置
    if (_resolved != null && state.firstFrameRendered) {
      _firstFrame ??= _watch.elapsed;
    }
    if (_resolved != null && state.videoViewAttached) {
      _viewAttached ??= _watch.elapsed;
    }
    if (!state.playing) return null;
    _firstPlaying ??= _watch.elapsed;
    final floor = target == null ? Duration.zero : target! - _targetTolerance;
    if (state.position < floor) {
      _anchor = null;
      return null;
    }
    final anchor = _anchor ??= state.position;
    if (state.buffering || state.position - anchor < _minProgress) return null;
    return PlaybackStartupReport(
      engine: engine,
      localFile: _localFile,
      target: target,
      resolved: _resolved,
      opened: _opened,
      firstPlaying: _firstPlaying,
      firstFrame: _firstFrame,
      viewAttached: _viewAttached,
      ready: _watch.elapsed,
    );
  }
}
