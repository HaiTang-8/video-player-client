import 'package:flutter/material.dart';
import '../window/window_controls.dart';

class WindowBorder extends StatefulWidget {
  final Widget child;
  const WindowBorder({required this.child, super.key});

  @override
  State<WindowBorder> createState() => _WindowBorderState();
}

class _WindowBorderState extends State<WindowBorder> with WidgetsBindingObserver {
  bool _isFullscreen = false;

  @override
  void initState() {
    super.initState();
    if (WindowControls.isDesktop) {
      WidgetsBinding.instance.addObserver(this);
      _checkFullscreen();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    _checkFullscreen();
  }

  Future<void> _checkFullscreen() async {
    final fullscreen = await WindowControls.isFullscreen();
    if (mounted && fullscreen != _isFullscreen) {
      setState(() => _isFullscreen = fullscreen);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!WindowControls.isDesktop || _isFullscreen) {
      return widget.child;
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = isDark
        ? const Color(0xFF3A3A3A)
        : const Color(0xFFD0D0D0);

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: borderColor, width: 1),
      ),
      child: ClipRect(child: widget.child),
    );
  }
}
