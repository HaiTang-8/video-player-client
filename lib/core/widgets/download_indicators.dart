import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// 带圆形进度环的下载图标
class DownloadProgressIcon extends StatelessWidget {
  final double progress;
  final double size;
  final Color? color;

  const DownloadProgressIcon({
    super.key,
    required this.progress,
    this.size = 28,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final iconColor = color ?? CupertinoColors.systemBlue;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: 1.0,
              strokeWidth: 2.5,
              color: iconColor.withValues(alpha: 0.2),
            ),
          ),
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: progress,
              strokeWidth: 2.5,
              color: iconColor,
              strokeCap: StrokeCap.round,
            ),
          ),
          Icon(
            CupertinoIcons.arrow_down,
            size: size * 0.5,
            color: iconColor,
          ),
        ],
      ),
    );
  }
}

/// 动态下载指示器（用于下载管理按钮旁）
class AnimatedDownloadIndicator extends StatefulWidget {
  final double size;
  final Color? color;

  const AnimatedDownloadIndicator({
    super.key,
    this.size = 20,
    this.color,
  });

  @override
  State<AnimatedDownloadIndicator> createState() => _AnimatedDownloadIndicatorState();
}

class _AnimatedDownloadIndicatorState extends State<AnimatedDownloadIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 2),
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
    final iconColor = widget.color ?? CupertinoColors.systemBlue;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Transform.rotate(
                angle: _controller.value * 2 * math.pi,
                child: CustomPaint(
                  size: Size(widget.size, widget.size),
                  painter: _ArcPainter(color: iconColor),
                ),
              ),
              Icon(
                CupertinoIcons.arrow_down,
                size: widget.size * 0.5,
                color: iconColor,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ArcPainter extends CustomPainter {
  final Color color;

  _ArcPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawArc(rect, -math.pi / 2, math.pi * 1.2, false, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
