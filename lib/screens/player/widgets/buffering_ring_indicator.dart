import 'package:flutter/material.dart';

import 'player_ui_metrics.dart';

class BufferingRingIndicator extends StatelessWidget {
  /// 0~1；为 null 时圆环内不显示百分比
  final double? progress;
  final String? label;

  const BufferingRingIndicator({super.key, this.progress, this.label});

  @override
  Widget build(BuildContext context) {
    final compact = PlayerUiMetrics.isCompact(context);
    final ringSize = compact ? 40.0 : 48.0;
    final progress = this.progress;
    final label = this.label;

    return Center(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.44),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: EdgeInsets.all(compact ? 10 : 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox.square(
                dimension: ringSize,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    const Positioned.fill(
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        strokeCap: StrokeCap.round,
                        color: Colors.white,
                        backgroundColor: Colors.white24,
                      ),
                    ),
                    if (progress != null)
                      Text(
                        '${(progress.clamp(0.0, 1.0) * 100).round()}%',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: compact ? 11 : 12,
                          fontWeight: FontWeight.w600,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                  ],
                ),
              ),
              if (label != null) ...[
                SizedBox(height: compact ? 6 : 8),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: compact ? 11 : 12,
                    fontWeight: FontWeight.w500,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
