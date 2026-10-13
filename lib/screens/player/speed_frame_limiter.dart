import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';

import '../../data/services/log_service.dart';

/// 倍速播放时均匀抽帧，使输出帧率不超过刷新率（高刷屏为刷新率的一半），
/// 让每帧占用固定数量的 vsync，避免出帧时钟与屏幕 vsync 不同步导致的顿挫。
class SpeedFrameLimiter {
  static const _label = '@speedfps';

  final Player _player;
  final List<StreamSubscription> _subscriptions = [];
  Future<void> _pending = Future.value();
  double? _appliedSourceFps;
  bool _disposed = false;

  SpeedFrameLimiter(this._player) {
    _subscriptions
      ..add(_player.stream.rate.listen((_) => _schedule()))
      ..add(_player.stream.videoParams.listen((_) => _schedule()));
  }

  static double? targetSourceFps({
    required double sourceFps,
    required double rate,
    required double refreshRate,
  }) {
    if (rate <= 1 || sourceFps <= 0 || refreshRate <= 0) return null;
    final outputCap = refreshRate >= 90 ? refreshRate / 2 : refreshRate;
    if (sourceFps * rate <= outputCap + 1) return null;
    return outputCap / rate;
  }

  void _schedule() {
    _pending = _pending.then((_) => _apply()).catchError((Object e) {
      LogService.instance.warn('SpeedFrameLimiter', 'Failed to apply: $e');
    });
  }

  double get _refreshRate {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    final rate = views.isEmpty ? 0.0 : views.first.display.refreshRate;
    return rate > 0 ? rate : 60;
  }

  Future<void> _apply() async {
    final platform = _player.platform;
    if (_disposed || platform is! NativePlayer) return;
    final sourceFps =
        double.tryParse(await platform.getProperty('container-fps')) ?? 0;
    final target = targetSourceFps(
      sourceFps: sourceFps,
      rate: _player.state.rate,
      refreshRate: _refreshRate,
    );
    if (_disposed || target == _appliedSourceFps) return;
    if (_appliedSourceFps != null) {
      await platform.command(['vf', 'remove', _label]);
    }
    if (target != null) {
      await platform.command([
        'vf',
        'add',
        '$_label:lavfi=[fps=fps=${target.toStringAsFixed(3)}]',
      ]);
    }
    _appliedSourceFps = target;
    LogService.instance.debug(
      'SpeedFrameLimiter',
      'sourceFps=$sourceFps, rate=${_player.state.rate}, '
          'refresh=$_refreshRate, target=$target',
    );
  }

  void dispose() {
    _disposed = true;
    for (final sub in _subscriptions) {
      sub.cancel();
    }
  }
}
