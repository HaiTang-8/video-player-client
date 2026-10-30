import 'package:flutter/material.dart';

/// 观看进度/总时长标签，叠加在卡片进度条上方
class WatchProgressLabel extends StatelessWidget {
  final int position;
  final int duration;

  const WatchProgressLabel({
    super.key,
    required this.position,
    required this.duration,
  });

  static String _format(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600 ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return h > 0 ? '${h.toString().padLeft(2, '0')}:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '${_format(position)}/${_format(duration)}',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}
