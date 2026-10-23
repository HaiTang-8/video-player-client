/// 用户字幕样式，各内核统一解释。颜色、背景、位置只作用于文本字幕，ASS / 位图字幕保留原样式
class SubtitleStyle {
  /// 字号倍率，1.0 为标准
  final double scale;

  /// ARGB
  final int color;

  /// 文字背后底框的不透明度，0 表示无底框
  final double backgroundOpacity;

  /// 字幕底部到画面底部的距离，占画面高度的比例
  final double bottomMargin;

  const SubtitleStyle({
    this.scale = 1.0,
    this.color = 0xFFFFFFFF,
    this.backgroundOpacity = 0.6,
    this.bottomMargin = 0.06,
  });

  static const defaults = SubtitleStyle();

  static const maxBottomMargin = 0.4;

  SubtitleStyle copyWith({
    double? scale,
    int? color,
    double? backgroundOpacity,
    double? bottomMargin,
  }) => SubtitleStyle(
    scale: scale ?? this.scale,
    color: color ?? this.color,
    backgroundOpacity: backgroundOpacity ?? this.backgroundOpacity,
    bottomMargin: bottomMargin ?? this.bottomMargin,
  );

  @override
  bool operator ==(Object other) =>
      other is SubtitleStyle &&
      other.scale == scale &&
      other.color == color &&
      other.backgroundOpacity == backgroundOpacity &&
      other.bottomMargin == bottomMargin;

  @override
  int get hashCode =>
      Object.hash(scale, color, backgroundOpacity, bottomMargin);
}
