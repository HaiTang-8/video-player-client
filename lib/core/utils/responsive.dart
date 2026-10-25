import 'package:flutter/widgets.dart';

enum WindowSizeClass {
  compact,
  medium,
  expanded;

  static WindowSizeClass fromWidth(double width) {
    if (width < 600) return WindowSizeClass.compact;
    if (width < 1024) return WindowSizeClass.medium;
    return WindowSizeClass.expanded;
  }

  bool get isCompact => this == WindowSizeClass.compact;
}

extension WindowSizeClassContext on BuildContext {
  WindowSizeClass get windowSizeClass =>
      WindowSizeClass.fromWidth(MediaQuery.sizeOf(this).width);
}
