import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/device/device_status.dart';
import 'player_glyphs.dart';

/// 网速、网络类型、电量；读不到的项不显示
class PlayerStatusBar extends StatefulWidget {
  static const textStyle = TextStyle(
    color: Colors.white,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  final Future<double?> Function()? fallbackSpeed;

  const PlayerStatusBar({super.key, this.fallbackSpeed});

  @override
  State<PlayerStatusBar> createState() => _PlayerStatusBarState();
}

class _PlayerStatusBarState extends State<PlayerStatusBar> {
  final _status = DeviceStatus.instance;
  Timer? _speedTimer;
  Timer? _batteryTimer;
  StreamSubscription<NetworkKind?>? _networkSub;
  StreamSubscription<void>? _batterySub;
  double? _speed;
  NetworkKind? _network;
  BatteryInfo? _battery;

  @override
  void initState() {
    super.initState();
    _speed = _status.lastSpeed;
    _sampleSpeed();
    _speedTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _sampleSpeed(),
    );
    _networkSub = _status.networkKind().listen((kind) {
      if (mounted) setState(() => _network = kind);
    });
    _refreshBattery();
    _batteryTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _refreshBattery(),
    );
    _batterySub = _status.batteryChanges.listen((_) => _refreshBattery());
  }

  Future<void> _sampleSpeed() async {
    final speed = await _status.sampleSpeed(fallback: widget.fallbackSpeed);
    if (mounted && speed != null) setState(() => _speed = speed);
  }

  Future<void> _refreshBattery() async {
    final battery = await _status.battery();
    if (mounted) setState(() => _battery = battery);
  }

  @override
  void dispose() {
    _speedTimer?.cancel();
    _batteryTimer?.cancel();
    _networkSub?.cancel();
    _batterySub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final network = _network;
    final battery = _battery;
    final items = <Widget>[
      if (_speed != null)
        Text(formatNetworkSpeed(_speed!), style: PlayerStatusBar.textStyle),
      if (network != null)
        PlayerGlyph(switch (network) {
          NetworkKind.wifi => PlayerGlyphType.wifi,
          NetworkKind.cellular => PlayerGlyphType.cellular,
          NetworkKind.ethernet => PlayerGlyphType.ethernet,
        }, size: 16),
      if (battery != null) _BatteryBadge(battery),
    ];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          items[i],
        ],
      ],
    );
  }
}

class _BatteryBadge extends StatelessWidget {
  final BatteryInfo info;

  const _BatteryBadge(this.info);

  @override
  Widget build(BuildContext context) {
    final low = info.level <= 20 && !info.charging;
    final Color body;
    final Color text;
    if (info.charging) {
      body = const Color(0xFF34C759);
      text = Colors.white;
    } else if (low) {
      body = const Color(0xFFFF3B30);
      text = Colors.white;
    } else {
      body = Colors.white;
      text = Colors.black;
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 24,
          height: 12,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: body,
            borderRadius: BorderRadius.circular(3.5),
          ),
          child: Text(
            '${info.level}',
            style: TextStyle(
              color: text,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              height: 1,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        Container(
          width: 1.5,
          height: 4,
          margin: const EdgeInsets.only(left: 1),
          decoration: BoxDecoration(
            color: body,
            borderRadius: const BorderRadius.horizontal(
              right: Radius.circular(1),
            ),
          ),
        ),
      ],
    );
  }
}
