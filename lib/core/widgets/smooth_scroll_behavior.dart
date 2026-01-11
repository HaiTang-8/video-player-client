import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

class SmoothScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.stylus,
        PointerDeviceKind.trackpad,
      };

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      return Scrollbar(controller: details.controller, child: child);
    }
    return super.buildScrollbar(context, child, details);
  }
}

class DesktopSmoothScroll extends StatefulWidget {
  final Widget child;
  final ScrollController controller;

  const DesktopSmoothScroll({
    super.key,
    required this.child,
    required this.controller,
  });

  static bool get enabled =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  @override
  State<DesktopSmoothScroll> createState() => _DesktopSmoothScrollState();
}

class _DesktopSmoothScrollState extends State<DesktopSmoothScroll> {
  double _targetOffset = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.controller.hasClients) {
        _targetOffset = widget.controller.offset;
      }
    });
    widget.controller.addListener(_syncOffset);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncOffset);
    super.dispose();
  }

  void _syncOffset() {
    if (widget.controller.hasClients &&
        !widget.controller.position.isScrollingNotifier.value) {
      _targetOffset = widget.controller.offset;
    }
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent && widget.controller.hasClients) {
      GestureBinding.instance.pointerSignalResolver.register(event, (event) {
        final pos = widget.controller.position;
        _targetOffset = (_targetOffset + (event as PointerScrollEvent).scrollDelta.dy).clamp(
          pos.minScrollExtent,
          pos.maxScrollExtent,
        );
        widget.controller.animateTo(
          _targetOffset,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!DesktopSmoothScroll.enabled) return widget.child;

    return Listener(
      onPointerSignal: _onPointerSignal,
      child: widget.child,
    );
  }
}
