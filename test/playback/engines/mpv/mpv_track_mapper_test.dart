import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_player/playback/domain/playback_domain.dart';
import 'package:media_player/playback/engines/mpv/mpv_track_mapper.dart';

void main() {
  test('drops auto / no pseudo tracks', () {
    final tracks = MpvTrackMapper.tracks(
      Tracks(
        audio: [
          AudioTrack.auto(),
          AudioTrack.no(),
          const AudioTrack('1', 'Main', 'chi'),
        ],
        subtitle: [
          SubtitleTrack.auto(),
          SubtitleTrack.no(),
          const SubtitleTrack('2', '简体', 'chi'),
        ],
      ),
    );
    expect(tracks.audio, const [
      AudioTrackInfo(id: '1', title: 'Main', language: 'chi'),
    ]);
    expect(tracks.subtitle, const [
      SubtitleTrackInfo(id: '2', title: '简体', language: 'chi'),
    ]);
  });

  test('maps selection state', () {
    final auto = MpvTrackMapper.selected(const Track());
    expect(auto.audio, isNull);
    expect(auto.subtitle, isNull);
    expect(auto.subtitleOff, isFalse);

    final off = MpvTrackMapper.selected(Track(subtitle: SubtitleTrack.no()));
    expect(off.subtitleOff, isTrue);
  });

  test('data subtitle gets a stable id instead of its content', () {
    final info = MpvTrackMapper.subtitle(
      SubtitleTrack.data('1\n00:00:01,000 --> 00:00:02,000\nhi', title: '外挂'),
    );
    expect(info.id, 'external:外挂');
    expect(info.title, '外挂');
  });

  test('converts back to native tracks', () {
    const available = Tracks(subtitle: [SubtitleTrack('3', 'Eng', 'eng')]);
    expect(MpvTrackMapper.toNativeSubtitle(null, available).id, 'no');
    final native = MpvTrackMapper.toNativeSubtitle(
      const SubtitleTrackInfo(id: '3'),
      available,
    );
    expect(native.title, 'Eng');
    expect(
      MpvTrackMapper.toNativeAudio(const AudioTrackInfo(id: '9'), available).id,
      '9',
    );
  });
}
