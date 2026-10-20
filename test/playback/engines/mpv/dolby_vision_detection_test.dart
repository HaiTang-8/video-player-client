import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/playback/domain/playback_domain.dart';
import 'package:media_player/playback/engines/mpv/dolby_vision_log_detector.dart';
import 'package:media_player/playback/engines/mpv/mpv_video_info.dart';

void main() {
  group('DolbyVisionLogDetector', () {
    test('reads profile from the container config record', () {
      final detector = DolbyVisionLogDetector();
      expect(
        detector.onLog(
          'lavf',
          'Found Dolby Vision config record: profile 8 level 6',
        ),
        isTrue,
      );
      expect(detector.profile, 8);
      expect(detector.detected, isTrue);
    });

    test('flags in-band RPU errors from the decoder once', () {
      final detector = DolbyVisionLogDetector();
      expect(
        detector.onLog(
          'ffmpeg/video',
          'hevc: RPU validation failed: 0 <= el_bit_depth_minus8 = 32 <= 8',
        ),
        isTrue,
      );
      expect(
        detector.onLog('ffmpeg/video', 'hevc: Error parsing DOVI NAL unit.'),
        isFalse,
      );
      expect(detector.detected, isTrue);
      expect(detector.profile, isNull);
    });

    test('ignores unrelated logs and resets per media', () {
      final detector = DolbyVisionLogDetector();
      expect(detector.onLog('cplayer', 'Playing: test.mkv'), isFalse);
      expect(detector.onLog('vd', 'Using software decoding.'), isFalse);
      expect(detector.detected, isFalse);

      detector.onLog('ffmpeg/video', 'hevc: Error parsing DOVI NAL unit.');
      detector.reset();
      expect(detector.detected, isFalse);
    });
  });

  group('MpvVideoInfo', () {
    test('maps gamma to dynamic range', () {
      expect(
        MpvVideoInfo.resolve(gamma: 'pq').dynamicRange,
        VideoDynamicRange.hdr10,
      );
      expect(
        MpvVideoInfo.resolve(gamma: 'hlg').dynamicRange,
        VideoDynamicRange.hlg,
      );
      expect(
        MpvVideoInfo.resolve(gamma: 'bt.1886').dynamicRange,
        VideoDynamicRange.sdr,
      );
      expect(MpvVideoInfo.resolve().dynamicRange, VideoDynamicRange.unknown);
    });

    test('dolby vision overrides gamma', () {
      const expected = VideoInfo(
        dynamicRange: VideoDynamicRange.dolbyVision,
        dolbyVisionProfile: 5,
      );
      expect(
        MpvVideoInfo.resolve(gamma: 'bt.1886', dolbyVisionProfile: 5),
        expected,
      );
      expect(
        MpvVideoInfo.resolve(gamma: 'pq', dolbyVision: true).dolbyVisionProfile,
        isNull,
      );
    });

    test('profile 5 inference requires unspecified decoder color params', () {
      expect(
        MpvVideoInfo.looksLikeProfile5(
          decoderColormatrix: 'auto',
          decoderGamma: 'auto',
        ),
        isTrue,
      );
      expect(
        MpvVideoInfo.looksLikeProfile5(
          decoderColormatrix: 'bt.2020-ncl',
          decoderGamma: 'pq',
        ),
        isFalse,
      );
    });
  });
}
