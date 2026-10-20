import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/playback/domain/playback_domain.dart';
import 'package:media_player/playback/session/subtitle_auto_selector.dart';

import '../fakes/fake_gateways.dart';

void main() {
  group('findChinese', () {
    test('prefers exact language code', () {
      const tracks = [
        SubtitleTrackInfo(id: '1', title: '中文', language: 'eng'),
        SubtitleTrackInfo(id: '2', language: 'chi'),
      ];
      expect(SubtitleAutoSelector.findChinese(tracks)?.id, '2');
    });

    test('falls back to title keyword, then zh prefix', () {
      expect(
        SubtitleAutoSelector.findChinese(const [
          SubtitleTrackInfo(id: '1', language: 'eng'),
          SubtitleTrackInfo(id: '2', title: 'Simplified Chinese'),
        ])?.id,
        '2',
      );
      expect(
        SubtitleAutoSelector.findChinese(const [
          SubtitleTrackInfo(id: '3', language: 'zh-tw'),
        ])?.id,
        '3',
      );
      expect(
        SubtitleAutoSelector.findChinese(const [
          SubtitleTrackInfo(id: '4', title: 'English', language: 'eng'),
        ]),
        isNull,
      );
    });
  });

  test('selects embedded track only once per load', () {
    final selector = SubtitleAutoSelector();
    const tracks = [SubtitleTrackInfo(id: '1', language: 'chi')];
    expect(selector.takeEmbedded(tracks)?.id, '1');
    expect(selector.takeEmbedded(tracks), isNull);

    selector.reset();
    selector.markDone();
    expect(selector.takeEmbedded(tracks), isNull);
  });

  test('auto loads external subtitle only above threshold', () {
    final selector = SubtitleAutoSelector();
    expect(selector.bestExternal(const []), isNull);
    expect(selector.bestExternal([subtitleInfo('a', 84)]), isNull);
    expect(
      selector.bestExternal([
        subtitleInfo('a', 85),
        subtitleInfo('b', 92),
      ])?.name,
      'b',
    );
  });
}
