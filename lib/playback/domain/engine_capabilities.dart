class EngineCapabilities {
  /// 能否正确还原杜比视界颜色（含 Profile 5）
  final bool dolbyVisionColor;

  /// 音量上限，1.0 = 100%
  final double maxVolume;

  final double maxRate;

  /// 画面在原生视图里（PlatformView），并上报视图是否已挂载（videoViewAttached）：
  /// 会话据此先暂停打开，视图挂载后再开始播放，避免画面还没显示就先出声
  final bool reportsVideoView;

  const EngineCapabilities({
    required this.dolbyVisionColor,
    required this.maxVolume,
    required this.maxRate,
    this.reportsVideoView = false,
  });
}
