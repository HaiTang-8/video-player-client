import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class TapFeedback extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Color overlayColor;
  final BorderRadius? borderRadius;
  final String? semanticLabel;

  const TapFeedback({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.overlayColor = Colors.black12,
    this.borderRadius,
    this.semanticLabel,
  });

  @override
  State<TapFeedback> createState() => _TapFeedbackState();
}

class _TapFeedbackState extends State<TapFeedback> {
  bool _isPressed = false;
  bool _isFocused = false;

  void _handleTapDown(TapDownDetails details) {
    setState(() => _isPressed = true);
  }

  void _handleTapUp(TapUpDetails details) {
    setState(() => _isPressed = false);
  }

  void _handleTapCancel() {
    setState(() => _isPressed = false);
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    final isActivateKey = event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.space;
    if (!isActivateKey) return KeyEventResult.ignored;

    // Trigger once on key-up to avoid key repeat spamming.
    if (event is KeyUpEvent) {
      widget.onTap?.call();
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    Widget content = GestureDetector(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        children: [
          widget.child,
          if (_isPressed || _isFocused)
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

    if (widget.onTap != null) {
      content = Focus(
        onKeyEvent: _handleKeyEvent,
        onFocusChange: (focused) => setState(() => _isFocused = focused),
        child: content,
      );
    }

    if (widget.semanticLabel != null) {
      content = Semantics(
        label: widget.semanticLabel,
        button: widget.onTap != null,
        child: content,
      );
    }

    return content;
  }
}
