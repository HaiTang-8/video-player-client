/// 用户设置的播放内核偏好
enum EnginePreference {
  /// 按平台自动选择，无法播放时回退
  auto('自动'),

  /// 始终使用 mpv
  compatibility('兼容模式');

  const EnginePreference(this.label);

  final String label;
}
