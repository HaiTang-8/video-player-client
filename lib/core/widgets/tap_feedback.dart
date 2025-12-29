import 'package:flutter/material.dart';

class TapFeedback extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Color overlayColor;
  final BorderRadius? borderRadius;

  const TapFeedback({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.overlayColor = Colors.black12,
    this.borderRadius,
  });

  @override
  State<TapFeedback> createState() => _TapFeedbackState();
}

class _TapFeedbackState extends State<TapFeedback> {
  bool _isPressed = false;

  void _handleTapDown(TapDownDetails details) {
    setState(() => _isPressed = true);
  }

  void _handleTapUp(TapUpDetails details) {
    setState(() => _isPressed = false);
  }

  void _handleTapCancel() {
    setState(() => _isPressed = false);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        children: [
          widget.child,
          if (_isPressed)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: widget.overlayColor,
                  borderRadius: widget.borderRadius,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
