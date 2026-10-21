class EngineCapabilities {
  /// 能否正确还原杜比视界颜色（含 Profile 5）
  final bool dolbyVisionColor;

  /// 音量上限，1.0 = 100%
  final double maxVolume;

  final double maxRate;

  const EngineCapabilities({
    required this.dolbyVisionColor,
    required this.maxVolume,
    required this.maxRate,
  });
}
