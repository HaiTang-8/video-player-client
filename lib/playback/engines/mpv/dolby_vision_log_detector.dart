/// 从 mpv 日志识别杜比视界（依据见任务文档 §5.1）：
/// - verbose 级的容器配置记录可以给出确切 profile
/// - 码流内 RPU 被 FFmpeg 判为非法时只能确认存在杜比视界
class DolbyVisionLogDetector {
  static final _configRecord = RegExp(
    r'Found Dolby Vision config record: profile (\d+)',
  );

  int? _profile;
  bool _rpuSeen = false;

  int? get profile => _profile;

  bool get detected => _profile != null || _rpuSeen;

  /// 检测结果有变化时返回 true
  bool onLog(String prefix, String text) {
    if (_profile == null) {
      final match = _configRecord.firstMatch(text);
      if (match != null) {
        _profile = int.tryParse(match.group(1)!);
        return true;
      }
    }
    if (!_rpuSeen &&
        prefix == 'ffmpeg/video' &&
        (text.contains('DOVI NAL unit') ||
            text.contains('RPU validation failed'))) {
      _rpuSeen = true;
      return true;
    }
    return false;
  }

  void reset() {
    _profile = null;
    _rpuSeen = false;
  }
}
