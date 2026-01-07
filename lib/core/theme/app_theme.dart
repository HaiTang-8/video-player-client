import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pull_down_button/pull_down_button.dart';
import '../widgets/ios_page_transition.dart';

/// 应用主题配置
class AppTheme {
  AppTheme._();

  static const String _fontFamily = 'HarmonyOS_Sans';

  static bool get _isWindows =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  static double? get _cupertinoLetterSpacing => _isWindows ? 0.0 : null;

  // 主色调 - iOS 蓝
  static const Color primaryColor = Color(0xFF007AFF);
  static const Color secondaryColor = Color(0xFF8B5CF6);

  /// 用于给各类（Material / Cupertino / 第三方 iOS 风格组件）统一注入字体的基础样式。
  ///
  /// 注意：只放“不会影响可读性/颜色”的字段（如 `fontFamily`、`letterSpacing`），
  /// 避免覆盖掉 Cupertino 默认的动态颜色（深色模式下输入框文字会变“看不见”）。
  static TextStyle get _baseTextStyle => TextStyle(
    fontFamily: _fontFamily,
    letterSpacing: _cupertinoLetterSpacing,
  );

  /// Cupertino 组件（对话框、输入框、导航栏等）在 iOS 上默认会带有负字距等排版参数，
  /// 但这些参数在 Windows 上配合自定义中文字体时容易出现“发虚/挤压/不自然”的观感。
  ///
  /// 这里基于 Flutter 的默认 `CupertinoTextThemeData()`（它包含动态颜色、字号、行高等），
  /// 仅覆盖字体族与 Windows 下的字距，从而：
  /// - 保留深色/浅色模式下的正确文字颜色（修复输入内容“看不见”）
  /// - 仅在 Windows 上去掉负字距，避免字体显示别扭
  static CupertinoTextThemeData get _cupertinoTextTheme {
    final defaults = CupertinoTextThemeData(primaryColor: primaryColor);
    final patch = _baseTextStyle;

    return defaults.copyWith(
      textStyle: defaults.textStyle.merge(patch),
      actionTextStyle: defaults.actionTextStyle.merge(patch),
      actionSmallTextStyle: defaults.actionSmallTextStyle.merge(patch),
      tabLabelTextStyle: defaults.tabLabelTextStyle.merge(patch),
      navTitleTextStyle: defaults.navTitleTextStyle.merge(patch),
      navLargeTitleTextStyle: defaults.navLargeTitleTextStyle.merge(patch),
      navActionTextStyle: defaults.navActionTextStyle.merge(patch),
      pickerTextStyle: defaults.pickerTextStyle.merge(patch),
      dateTimePickerTextStyle: defaults.dateTimePickerTextStyle.merge(patch),
    );
  }

  static PullDownButtonTheme get _pullDownButtonTheme {
    final base = _baseTextStyle.copyWith(
      letterSpacing: _isWindows ? 0.0 : null,
    );
    return PullDownButtonTheme(
      titleTheme: PullDownMenuTitleTheme(
        style: base.copyWith(letterSpacing: null),
      ),
      itemTheme: PullDownMenuItemTheme(
        textStyle: base,
        subtitleStyle: base,
        iconActionTextStyle: base,
      ),
    );
  }

  // 亮色主题
  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    fontFamily: _fontFamily,
    scaffoldBackgroundColor: const Color(0xFFF5F5F5),
    cupertinoOverrideTheme: CupertinoThemeData(textTheme: _cupertinoTextTheme),
    extensions: <ThemeExtension<dynamic>>[_pullDownButtonTheme],
    colorScheme: ColorScheme.fromSeed(
      seedColor: primaryColor,
      brightness: Brightness.light,
      surface: Colors.white,
    ),
    appBarTheme: const AppBarTheme(
      centerTitle: true,
      elevation: 0,
      toolbarHeight: 44,
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        color: Colors.black,
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Colors.white,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      indicatorColor: primaryColor.withValues(alpha: 0.15),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.iOS: IosPageTransitionsBuilder(),
        TargetPlatform.android: IosPageTransitionsBuilder(),
        TargetPlatform.macOS: IosPageTransitionsBuilder(),
        TargetPlatform.windows: IosPageTransitionsBuilder(),
        TargetPlatform.linux: IosPageTransitionsBuilder(),
      },
    ),
  );

  // 暗色主题
  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    fontFamily: _fontFamily,
    cupertinoOverrideTheme: CupertinoThemeData(textTheme: _cupertinoTextTheme),
    extensions: <ThemeExtension<dynamic>>[_pullDownButtonTheme],
    colorScheme: ColorScheme.fromSeed(
      seedColor: primaryColor,
      brightness: Brightness.dark,
    ),
    scaffoldBackgroundColor: const Color(0xFF0F0F0F),
    appBarTheme: const AppBarTheme(
      centerTitle: true,
      elevation: 0,
      toolbarHeight: 44,
      backgroundColor: Color(0xFF1A1A1A),
      titleTextStyle: TextStyle(
        color: Colors.white,
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 2,
      color: const Color(0xFF1A1A1A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF1A1A1A),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Color(0xFF1A1A1A),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: const Color(0xFF1A1A1A),
      indicatorColor: primaryColor.withValues(alpha: 0.2),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.iOS: IosPageTransitionsBuilder(),
        TargetPlatform.android: IosPageTransitionsBuilder(),
        TargetPlatform.macOS: IosPageTransitionsBuilder(),
        TargetPlatform.windows: IosPageTransitionsBuilder(),
        TargetPlatform.linux: IosPageTransitionsBuilder(),
      },
    ),
  );
}
