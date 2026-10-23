/// 平移外挂字幕文本的时间轴，用于不支持字幕偏移的内核。
/// 认 SRT / WebVTT 的时间行（含 `-->`）和 ASS / SSA 的 Dialogue 行，其余内容原样保留
class SubtitleTimeShifter {
  const SubtitleTimeShifter._();

  static final _cueTime = RegExp(r'(?:(\d+):)?(\d{1,2}):(\d{2})([,.])(\d{3})');
  static final _dialogue = RegExp(
    r'^(Dialogue:\s*[^,]*,)(\d+):(\d{2}):(\d{2})\.(\d{2}),(\d+):(\d{2}):(\d{2})\.(\d{2}),',
  );

  /// 正值表示字幕延后显示，平移后早于 0 的时间按 0 处理
  static String shift(String text, Duration offset) {
    if (offset == Duration.zero) return text;
    final ms = offset.inMilliseconds;
    final lines = text.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.contains('-->')) {
        lines[i] = line.replaceAllMapped(_cueTime, (m) => _cue(m, ms));
      } else if (line.startsWith('Dialogue:')) {
        lines[i] = line.replaceFirstMapped(
          _dialogue,
          (m) => '${m[1]}${_ass(m, 2, ms)},${_ass(m, 6, ms)},',
        );
      }
    }
    return lines.join('\n');
  }

  static String _cue(Match m, int offsetMs) {
    final total =
        (int.parse(m[1] ?? '0') * 3600 +
                int.parse(m[2]!) * 60 +
                int.parse(m[3]!)) *
            1000 +
        int.parse(m[5]!) +
        offsetMs;
    final t = total < 0 ? 0 : total;
    final h = t ~/ 3600000;
    final min = t ~/ 60000 % 60;
    final s = t ~/ 1000 % 60;
    final frac = (t % 1000).toString().padLeft(3, '0');
    final mmss = '${_two(min)}:${_two(s)}${m[4]}$frac';
    return m[1] == null && h == 0 ? mmss : '${_two(h)}:$mmss';
  }

  static String _ass(Match m, int group, int offsetMs) {
    final total =
        (int.parse(m[group]!) * 3600 +
                int.parse(m[group + 1]!) * 60 +
                int.parse(m[group + 2]!)) *
            1000 +
        int.parse(m[group + 3]!) * 10 +
        offsetMs;
    final t = total < 0 ? 0 : total;
    return '${t ~/ 3600000}:${_two(t ~/ 60000 % 60)}:${_two(t ~/ 1000 % 60)}.'
        '${_two(t % 1000 ~/ 10)}';
  }

  static String _two(int v) => v.toString().padLeft(2, '0');
}
