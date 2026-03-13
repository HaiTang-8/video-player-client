import 'dart:math' as math;

import 'package:flutter/material.dart';

class RippleLoadingIndicator extends StatefulWidget {
  final String? speedText;
  final String? hintText;
  final double size;

  const RippleLoadingIndicator({
    super.key,
    this.speedText,
    this.hintText,
    this.size = 80,
  });

  @override
  State<RippleLoadingIndicator> createState() => _RippleLoadingIndicatorState();
}

class _RippleLoadingIndicatorState extends State<RippleLoadingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  static const _rippleCount = 3;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black38,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
          SizedBox(
            width: widget.size,
            height: widget.size,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                return CustomPaint(
                  painter: _RipplePainter(
                    progress: _controller.value,
                    rippleCount: _rippleCount,
                  ),
                );
              },
            ),
          ),
          if (widget.speedText != null) ...[
            const SizedBox(height: 12),
            Text(
              widget.speedText!,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
          if (widget.hintText != null) ...[
            SizedBox(height: widget.speedText != null ? 4 : 12),
            Text(
              widget.hintText!,
              style: const TextStyle(color: Colors.white54, fontSize: 14),
            ),
          ],
        ],
          ),
        ),
      ),
    );
  }
}

class _RipplePainter extends CustomPainter {
  final double progress;
  final int rippleCount;

  _RipplePainter({required this.progress, required this.rippleCount});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = math.min(size.width, size.height) / 2;

    for (var i = 0; i < rippleCount; i++) {
      final phase = (progress + i / rippleCount) % 1.0;
      final radius = maxRadius * phase;
      final opacity = (1.0 - phase) * 0.6;

      final paint = Paint()
        ..color = Colors.white.withValues(alpha: opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;

      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(_RipplePainter oldDelegate) =>
      oldDelegate.progress != progress;
}
