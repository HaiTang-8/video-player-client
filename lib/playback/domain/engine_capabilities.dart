class EngineCapabilities {
  /// 能否正确还原杜比视界颜色（含 Profile 5）
  final bool dolbyVisionColor;

  /// 音量上限，1.0 = 100%
  final double maxVolume;

  final double maxRate;

  /// 画面在原生视图里（PlatformView），并上报视图是否已挂载（videoViewAttached）：
  /// 会话据此先暂停打开，视图挂载后再开始播放，避免画面还没显示就先出声
  final bool reportsVideoView;

  /// 支持对所有字幕设置偏移；不支持时会话只能平移外挂字幕的时间轴后重新加载
  final bool subtitleDelay;

  /// 卡顿或跳转后，前方缓冲到多长内核才恢复播放；UI 据此估算缓冲百分比
  final Duration bufferingTarget;

  /// 内核自己上报缓冲进度（PlaybackSnapshot.bufferingProgress）；否则 UI 按 bufferingTarget 估算
  final bool reportsBufferingProgress;

  const EngineCapabilities({
    required this.dolbyVisionColor,
    required this.maxVolume,
    required this.maxRate,
    this.reportsVideoView = false,
    this.subtitleDelay = false,
    this.bufferingTarget = const Duration(seconds: 3),
    this.reportsBufferingProgress = false,
  });
}
