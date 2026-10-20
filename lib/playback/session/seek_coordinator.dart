import 'dart:async';

import '../../data/services/log_service.dart';
import '../domain/playback_domain.dart';

/// 串行化用户 seek：新的 seek 会让旧 seek 的收尾逻辑失效
class SeekCoordinator {
  SeekCoordinator({
    required PlaybackEngine engine,
    required void Function(Duration target) onSeekStarted,
    required Future<void> Function() onSeekSettled,
    this.pollInterval = const Duration(milliseconds: 150),
  }) : _engine = engine,
       _onSeekStarted = onSeekStarted,
       _onSeekSettled = onSeekSettled;

  static const _positionToleranceMs = 1000;
  static const _maxPolls = 10;

  final PlaybackEngine _engine;
  final void Function(Duration target) _onSeekStarted;
  final Future<void> Function() _onSeekSettled;
  final Duration pollInterval;

  int _version = 0;
  Future<void>? _active;

  bool get isActive => _active != null;

  /// 返回的 Future 在引擎完成 seek 时结束，错误会被吞掉
  Future<void> seek(Duration position) {
    final version = ++_version;
    _onSeekStarted(position);

    final seekFuture = Future<void>.sync(() => _engine.seek(position));
    final operation = _settle(position, version, seekFuture);
    _active = operation;
    unawaited(
      operation.whenComplete(() {
        if (identical(_active, operation)) _active = null;
      }),
    );
    return seekFuture.catchError((_) {});
  }

  Future<void> awaitActive() async {
    final operation = _active;
    if (operation == null) return;
    try {
      await operation;
    } catch (_) {}
  }

  Future<void> _settle(
    Duration target,
    int version,
    Future<void> seekFuture,
  ) async {
    try {
      await seekFuture;
      if (version != _version) return;
      await _waitForPosition(target, version);
      if (version != _version) return;
      await _onSeekSettled();
    } catch (e) {
      LogService.instance.warn('SeekCoordinator', 'User seek failed: $e');
    }
  }

  Future<void> _waitForPosition(Duration target, int version) async {
    for (var i = 0; i < _maxPolls; i++) {
      if (version != _version) return;
      final current = _engine.state.position;
      if ((current.inMilliseconds - target.inMilliseconds).abs() <=
          _positionToleranceMs) {
        return;
      }
      await Future<void>.delayed(pollInterval);
    }
  }
}
