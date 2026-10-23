import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/playback/session/subtitle_time_shifter.dart';

void main() {
  test('shifts SRT cue times and clamps at zero', () {
    const srt = '1\n00:00:00,300 --> 00:59:59,900\nline\n';
    expect(
      SubtitleTimeShifter.shift(srt, const Duration(milliseconds: 200)),
      '1\n00:00:00,500 --> 01:00:00,100\nline\n',
    );
    expect(
      SubtitleTimeShifter.shift(srt, const Duration(milliseconds: -500)),
      '1\n00:00:00,000 --> 00:59:59,400\nline\n',
    );
  });

  test('keeps the WebVTT short form', () {
    const vtt = 'WEBVTT\n\n01:02.500 --> 01:04.000 line:90%\ntext';
    expect(
      SubtitleTimeShifter.shift(vtt, const Duration(seconds: 1)),
      'WEBVTT\n\n01:03.500 --> 01:05.000 line:90%\ntext',
    );
  });

  test('shifts ASS dialogue start and end only', () {
    const ass =
        '[Events]\n'
        'Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n'
        'Dialogue: 0,0:00:01.50,0:00:03.00,Default,,0,0,0,,{\\pos(1,2)}0:00:09.00';
    expect(
      SubtitleTimeShifter.shift(ass, const Duration(milliseconds: -250)),
      '[Events]\n'
      'Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n'
      'Dialogue: 0,0:00:01.25,0:00:02.75,Default,,0,0,0,,{\\pos(1,2)}0:00:09.00',
    );
  });
}
