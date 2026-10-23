import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/services.dart';

enum NetworkKind { wifi, cellular, ethernet }

class BatteryInfo {
  final int level;
  final bool charging;

  const BatteryInfo(this.level, {required this.charging});
}

String formatNetworkSpeed(double bytesPerSecond) {
  if (bytesPerSecond < 1024) return '${bytesPerSecond.toStringAsFixed(0)} B/s';
  final kb = bytesPerSecond / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(0)} KB/s';
  return '${(kb / 1024).toStringAsFixed(1)} MB/s';
}

/// 设备级状态：下行网速（原生累计字节差值）、网络类型、电量
class DeviceStatus {
  DeviceStatus._();

  static final instance = DeviceStatus._();

  static const _channel = MethodChannel('media_player/device_status');

  final _battery = Battery();
  final _connectivity = Connectivity();
  bool _nativeRxUnavailable = false;
  int? _lastRxBytes;
  DateTime? _lastRxAt;

  /// 最近一次得到的网速，控制层重新显示时先用它占位
  double? lastSpeed;

  /// 原生计数不可用（如 Windows）时改用 [fallback]；首次采样只建立基线，返回 [lastSpeed]
  Future<double?> sampleSpeed({Future<double?> Function()? fallback}) async {
    if (!_nativeRxUnavailable) {
      try {
        final bytes = await _channel.invokeMethod<int>('rxBytes');
        if (bytes != null) return lastSpeed = _speedFrom(bytes) ?? lastSpeed;
      } on MissingPluginException {
        _nativeRxUnavailable = true;
      } on PlatformException {
        _nativeRxUnavailable = true;
      }
    }
    if (fallback == null) return null;
    return lastSpeed = await fallback() ?? 0;
  }

  double? _speedFrom(int bytes) {
    final now = DateTime.now();
    final last = _lastRxBytes;
    final lastAt = _lastRxAt;
    _lastRxBytes = bytes;
    _lastRxAt = now;
    if (last == null || lastAt == null) return null;
    final seconds = now.difference(lastAt).inMilliseconds / 1000;
    if (seconds <= 0 || seconds > 5) return null;
    final delta = bytes - last;
    return delta < 0 ? 0 : delta / seconds;
  }

  Stream<NetworkKind?> networkKind() async* {
    try {
      yield _kindOf(await _connectivity.checkConnectivity());
      yield* _connectivity.onConnectivityChanged.map(_kindOf);
    } on PlatformException {
      yield null;
    }
  }

  static NetworkKind? _kindOf(List<ConnectivityResult> results) {
    for (final (result, kind) in const [
      (ConnectivityResult.ethernet, NetworkKind.ethernet),
      (ConnectivityResult.wifi, NetworkKind.wifi),
      (ConnectivityResult.mobile, NetworkKind.cellular),
    ]) {
      if (results.contains(result)) return kind;
    }
    return null;
  }

  /// 读不到电池（台式机、模拟器）时返回 null
  Future<BatteryInfo?> battery() async {
    try {
      final state = await _battery.batteryState;
      if (state == BatteryState.unknown) return null;
      final level = await _battery.batteryLevel;
      if (level <= 0 || level > 100) return null;
      return BatteryInfo(
        level,
        charging: state == BatteryState.charging || state == BatteryState.full,
      );
    } catch (_) {
      return null;
    }
  }

  Stream<void> get batteryChanges =>
      _battery.onBatteryStateChanged.handleError((_) {});
}
