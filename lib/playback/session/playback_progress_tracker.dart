import 'dart:async';

import '../../data/services/log_service.dart';
import '../domain/playback_domain.dart';
import 'playback_gateways.dart';
import 'playback_item.dart';

/// 观看进度的定时保存，以及网络异常后“误报接近结尾”位置的识别
class PlaybackProgressTracker {
  PlaybackProgressTracker({
    required PlaybackEngine engine,
    required WatchProgressGateway gateway,
    required bool Function() isSeeking,
    DateTime Function()? clock,
    this.interval = const Duration(seconds: 10),
  }) : _engine = engine,
       _gateway = gateway,
       _isSeeking = isSeeking,
       _now = clock ?? DateTime.now;

  final PlaybackEngine _engine;
  final WatchProgressGateway _gateway;
  final bool Function() _isSeeking;
  final DateTime Function() _now;
  final Duration interval;

  PlaybackItem? _item;
  Timer? _timer;
  Duration _lastSavedPosition = Duration.zero;
  DateTime? _lastNetworkErrorAt;
  Duration? _networkErrorPosition;
  Duration _lastTrustedPosition = Duration.zero;
  bool _lastPositionWasSuspiciousEnd = false;
  DateTime? _lastControlledSeekAt;
  Duration? _lastControlledSeekTarget;

  void start(PlaybackItem item) {
    _item = item;
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => unawaited(save()));
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void onPosition(Duration position) {
    if (_isSuspiciousEndPosition(position, _engine.state.duration)) {
      _lastPositionWasSuspiciousEnd = true;
      return;
    }
    _lastPositionWasSuspiciousEnd = false;
    if (position >= Duration.zero) _lastTrustedPosition = position;
  }

  void markNetworkError() {
    _lastNetworkErrorAt = _now();
    _networkErrorPosition = _lastTrustedPosition;
  }

  void markControlledSeek(Duration target) {
    _lastControlledSeekAt = _now();
    _lastControlledSeekTarget = target;
    _lastTrustedPosition = target;
    _lastPositionWasSuspiciousEnd = false;
  }

  void resetErrorTracking() {
    _lastNetworkErrorAt = null;
    _networkErrorPosition = null;
    _lastTrustedPosition = Duration.zero;
    _lastPositionWasSuspiciousEnd = false;
    _lastControlledSeekAt = null;
    _lastControlledSeekTarget = null;
  }

  bool get hasRecentNetworkError {
    final lastErrorAt = _lastNetworkErrorAt;
    if (lastErrorAt == null) return false;
    return _now().difference(lastErrorAt) <= const Duration(seconds: 45);
  }

  bool isSuspiciousCompletion() =>
      _lastPositionWasSuspiciousEnd ||
      _isSuspiciousEndPosition(_engine.state.position, _engine.state.duration);

  Future<void> save({bool force = false, bool fromCompleted = false}) async {
    try {
      if (!force && _isSeeking()) return;
      final item = _item;
      if (item == null) return;
      final position = _engine.state.position;
      final duration = _engine.state.duration;

      // 跳过无效数据或位置未变化
      if (duration.inSeconds <= 0) return;
      if (_shouldSkipSave(
        position,
        duration,
        force: force,
        fromCompleted: fromCompleted,
      )) {
        LogService.instance.warn(
          'PlaybackProgress',
          'Skipped suspicious progress save: ${position.inSeconds}/${duration.inSeconds}',
        );
        return;
      }
      if (!force && position == _lastSavedPosition) return;
      if (!_gateway.isAvailable) return;

      await _gateway.upload(item, position, duration);
      _gateway.publish(item, position, duration);
      _lastSavedPosition = position;
    } catch (e) {
      LogService.instance.warn(
        'PlaybackProgress',
        'Failed to save progress: $e',
      );
    }
  }

  /// 同步版本，用于页面销毁时的最后一次保存，不等待上报结果
  void saveSync() {
    try {
      final item = _item;
      if (item == null) return;
      final position = _engine.state.position;
      final duration = _engine.state.duration;
      if (duration.inSeconds <= 0 || position == _lastSavedPosition) return;
      if (_shouldSkipSave(
        position,
        duration,
        force: false,
        fromCompleted: false,
      )) {
        return;
      }
      if (!_gateway.isAvailable) return;
      _gateway.publish(item, position, duration);
      _gateway.upload(item, position, duration).ignore();
    } catch (_) {
      // 静默失败，不阻塞销毁
    }
  }

  bool _isRecentControlledSeekPosition(Duration position) {
    final target = _lastControlledSeekTarget;
    final seekAt = _lastControlledSeekAt;
    if (target == null || seekAt == null) return false;
    if (_now().difference(seekAt) > const Duration(seconds: 20)) return false;
    return (position.inMilliseconds - target.inMilliseconds).abs() <= 1500;
  }

  bool _isNearPlaybackEnd(Duration position, Duration duration) {
    if (duration.inSeconds <= 180) return false;
    return position >= duration - const Duration(seconds: 60);
  }

  bool _isSuspiciousEndPosition(Duration position, Duration duration) {
    if (!hasRecentNetworkError) return false;
    if (!_isNearPlaybackEnd(position, duration)) return false;
    if (_isRecentControlledSeekPosition(position)) return false;
    final trusted = _networkErrorPosition ?? _lastTrustedPosition;
    if (trusted <= Duration.zero) return false;
    if (_isNearPlaybackEnd(trusted, duration)) return false;
    return position - trusted >= const Duration(seconds: 30);
  }

  bool _shouldSkipSave(
    Duration position,
    Duration duration, {
    required bool force,
    required bool fromCompleted,
  }) {
    if (force && _isRecentControlledSeekPosition(position)) return false;
    if (fromCompleted && !isSuspiciousCompletion()) return false;
    return _lastPositionWasSuspiciousEnd ||
        _isSuspiciousEndPosition(position, duration);
  }
}
