import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:scroll_animator/scroll_animator.dart';

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

class DesktopSmoothScroll extends StatelessWidget {
  final Widget child;

  const DesktopSmoothScroll({
    super.key,
    required this.child,
  });

  static bool get isDesktop =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  @override
  Widget build(BuildContext context) {
    if (!isDesktop) {
      return child;
    }
    return AnimatedPrimaryScrollController(
      animationFactory: const ChromiumEaseInOut(),
      child: Focus(
        autofocus: true,
        child: child,
      ),
    );
  }
}
