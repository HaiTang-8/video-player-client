import 'package:flutter/material.dart';

@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.cardBackground,
    required this.cardBackgroundSecondary,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.iconPrimary,
    required this.iconSecondary,
    required this.divider,
    required this.surfaceOverlay,
    required this.groupedBackground,
  });

  final Color cardBackground;
  final Color cardBackgroundSecondary;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color iconPrimary;
  final Color iconSecondary;
  final Color divider;
  final Color surfaceOverlay;
  final Color groupedBackground;

  static const light = AppColors(
    cardBackground: Colors.white,
    cardBackgroundSecondary: Color(0xFFF5F5F5),
    textPrimary: Colors.black,
    textSecondary: Color(0xFF666666),
    textTertiary: Color(0xFF999999),
    iconPrimary: Colors.black,
    iconSecondary: Color(0xFF666666),
    divider: Color(0xFFE5E5E5),
    surfaceOverlay: Color(0x0A000000),
    groupedBackground: Color(0xFFF2F2F7),
  );

  static const dark = AppColors(
    cardBackground: Color(0xFF1C1C1E),
    cardBackgroundSecondary: Color(0xFF2C2C2E),
    textPrimary: Colors.white,
    textSecondary: Color(0xFFAAAAAA),
    textTertiary: Color(0xFF666666),
    iconPrimary: Colors.white,
    iconSecondary: Color(0xFFAAAAAA),
    divider: Color(0xFF3A3A3C),
    surfaceOverlay: Color(0x0AFFFFFF),
    groupedBackground: Color(0xFF000000),
  );

  @override
  AppColors copyWith({
    Color? cardBackground,
    Color? cardBackgroundSecondary,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? iconPrimary,
    Color? iconSecondary,
    Color? divider,
    Color? surfaceOverlay,
    Color? groupedBackground,
  }) {
    return AppColors(
      cardBackground: cardBackground ?? this.cardBackground,
      cardBackgroundSecondary: cardBackgroundSecondary ?? this.cardBackgroundSecondary,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      iconPrimary: iconPrimary ?? this.iconPrimary,
      iconSecondary: iconSecondary ?? this.iconSecondary,
      divider: divider ?? this.divider,
      surfaceOverlay: surfaceOverlay ?? this.surfaceOverlay,
      groupedBackground: groupedBackground ?? this.groupedBackground,
    );
  }

  @override
  AppColors lerp(AppColors? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      cardBackground: Color.lerp(cardBackground, other.cardBackground, t)!,
      cardBackgroundSecondary: Color.lerp(cardBackgroundSecondary, other.cardBackgroundSecondary, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      iconPrimary: Color.lerp(iconPrimary, other.iconPrimary, t)!,
      iconSecondary: Color.lerp(iconSecondary, other.iconSecondary, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      surfaceOverlay: Color.lerp(surfaceOverlay, other.surfaceOverlay, t)!,
      groupedBackground: Color.lerp(groupedBackground, other.groupedBackground, t)!,
    );
  }
}

extension AppColorsExtension on BuildContext {
  AppColors get appColors => Theme.of(this).extension<AppColors>() ?? AppColors.light;
}
