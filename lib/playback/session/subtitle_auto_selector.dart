import '../../data/models/subtitle_info.dart';
import '../domain/playback_domain.dart';

/// 每次加载只自动选择一次字幕：外挂高分字幕优先，否则选内嵌简体中文
class SubtitleAutoSelector {
  static const externalAutoLoadScore = 85;

  static const _chineseLanguages = [
    'zh',
    'chi',
    'zho',
    'zh-cn',
    'zh-hans',
    'chs',
    'sc',
  ];
  static const _chineseTitleKeywords = [
    '简体',
    '简中',
    'chs',
    'sc',
    'simplified',
    '中文',
    'chinese',
  ];

  bool _done = false;

  void reset() => _done = false;

  void markDone() => _done = true;

  SubtitleInfo? bestExternal(List<SubtitleInfo> subtitles) {
    if (subtitles.isEmpty) return null;
    final best = subtitles.reduce((a, b) => a.score >= b.score ? a : b);
    return best.score >= externalAutoLoadScore ? best : null;
  }

  SubtitleTrackInfo? takeEmbedded(List<SubtitleTrackInfo> tracks) {
    if (_done) return null;
    final track = findChinese(tracks);
    if (track != null) _done = true;
    return track;
  }

  static SubtitleTrackInfo? findChinese(List<SubtitleTrackInfo> tracks) {
    for (final track in tracks) {
      final lang = track.language?.toLowerCase() ?? '';
      if (_chineseLanguages.contains(lang)) return track;
    }

    for (final track in tracks) {
      final title = track.title?.toLowerCase() ?? '';
      for (final keyword in _chineseTitleKeywords) {
        if (title.contains(keyword.toLowerCase())) return track;
      }
    }

    for (final track in tracks) {
      final lang = track.language?.toLowerCase() ?? '';
      if (lang.startsWith('zh')) return track;
    }

    return null;
  }
}
