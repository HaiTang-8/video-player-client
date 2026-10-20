import 'package:media_kit/media_kit.dart';

import '../../domain/playback_domain.dart';

/// media_kit 轨道与领域轨道模型的互相转换；mpv 的 auto / no 伪轨道不进入领域层
abstract final class MpvTrackMapper {
  static const _externalPrefix = 'external:';

  static MediaTracks tracks(Tracks tracks) => MediaTracks(
    audio: [
      for (final t in tracks.audio)
        if (!_isPseudo(t.id)) audio(t),
    ],
    subtitle: [
      for (final t in tracks.subtitle)
        if (!_isPseudo(t.id)) subtitle(t),
    ],
  );

  static SelectedTracks selected(Track track) => SelectedTracks(
    audio: _isPseudo(track.audio.id) ? null : audio(track.audio),
    subtitle: _isPseudo(track.subtitle.id) ? null : subtitle(track.subtitle),
    subtitleOff: track.subtitle.id == 'no',
  );

  static AudioTrackInfo audio(AudioTrack track) => AudioTrackInfo(
    id: track.id,
    title: track.title,
    language: track.language,
  );

  /// 以文本加载的外挂字幕在 media_kit 中以整段文本作为 id，这里换成稳定的 id
  static SubtitleTrackInfo subtitle(SubtitleTrack track) => SubtitleTrackInfo(
    id: track.data ? '$_externalPrefix${track.title ?? ''}' : track.id,
    title: track.title,
    language: track.language,
  );

  static AudioTrack toNativeAudio(AudioTrackInfo info, Tracks available) =>
      available.audio.where((t) => t.id == info.id).firstOrNull ??
      AudioTrack(info.id, info.title, info.language);

  static SubtitleTrack toNativeSubtitle(
    SubtitleTrackInfo? info,
    Tracks available,
  ) {
    if (info == null) return SubtitleTrack.no();
    return available.subtitle.where((t) => t.id == info.id).firstOrNull ??
        SubtitleTrack(info.id, info.title, info.language);
  }

  static bool _isPseudo(String id) => id == 'auto' || id == 'no';
}
