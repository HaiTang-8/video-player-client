import 'package:flutter/material.dart';

class RippleLoadingIndicator extends StatefulWidget {
  final String? speedText;
  final String? hintText;
  final double width;
  final double height;

  const RippleLoadingIndicator({
    super.key,
    this.speedText,
    this.hintText,
    this.width = 96,
    this.height = 5,
  });

  @override
  State<RippleLoadingIndicator> createState() => _RippleLoadingIndicatorState();
}

class _RippleLoadingIndicatorState extends State<RippleLoadingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

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
    final screenWidth = MediaQuery.sizeOf(context).width;
    final maxWidth = (screenWidth - 48).clamp(180.0, 320.0);
    final hintText = widget.hintText;
    final speedText = widget.speedText;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.44),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: widget.width,
                  height: widget.height,
                  child: AnimatedBuilder(
                    animation: _controller,
                    builder: (context, _) {
                      return CustomPaint(
                        painter: _PulseBarPainter(progress: _controller.value),
                      );
                    },
                  ),
                ),
                if (hintText != null) ...[
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      hintText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
                if (speedText != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    speedText,
                    maxLines: 1,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PulseBarPainter extends CustomPainter {
  final double progress;

  _PulseBarPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final radius = Radius.circular(size.height / 2);
    final rect = Offset.zero & size;
    final trackPaint = Paint()..color = Colors.white.withValues(alpha: 0.18);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, radius), trackPaint);

    final segmentWidth = size.width * 0.38;
    final travel = size.width + segmentWidth;
    final left = progress * travel - segmentWidth;
    final segmentRect = Rect.fromLTWH(left, 0, segmentWidth, size.height);
    final highlightPaint =
        Paint()
          ..shader = LinearGradient(
            colors: [
              Colors.white.withValues(alpha: 0),
              Colors.white.withValues(alpha: 0.85),
              Colors.white.withValues(alpha: 0),
            ],
          ).createShader(segmentRect);

    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(rect, radius));
    canvas.drawRect(segmentRect, highlightPaint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PulseBarPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
