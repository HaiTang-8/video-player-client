import 'package:flutter/widgets.dart';

import '../../../core/window/window_controls.dart';

abstract final class PlayerUiMetrics {
  static const double edge = 16;
  static const double toolIcon = 24;
  static const double transportIcon = 26;
  static const double playIcon = 32;
  static const double transportHit = 48;
  static const double toolSpacing = 8;
  static const double titleSize = 18;
  static const double timeSize = 13;
  static const double speedSize = 16;

  static double get hit => WindowControls.isDesktop ? 48 : 44;

  /// 工具按钮内容两侧的留白，文字按钮与图标按钮共用，保证相邻间距一致
  static double get toolInset => (hit - toolIcon) / 2;

  static bool isCompact(BuildContext context) =>
      MediaQuery.sizeOf(context).shortestSide < 600;
}
