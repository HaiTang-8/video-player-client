import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/playback/domain/playback_domain.dart';
import 'package:media_player/screens/player/widgets/media_info_rows.dart';

void main() {
  test('common rows come first in a fixed order', () {
    final rows = buildMediaInfoRows(
      engine: PlaybackEngineKind.media3,
      engineReason: 'Android 优先使用 Media3',
      videoInfo: const VideoInfo(
        dynamicRange: VideoDynamicRange.dolbyVision,
        dolbyVisionProfile: 5,
      ),
      diagnostics: const MediaDiagnostics(
        videoDecoder: 'c2.qti.hevc.decoder',
        outputDynamicRange: VideoDynamicRange.hdr10,
        details: {'视频编码': 'HEVC', '杜比视界处理': 'GPU 重建为 HDR10'},
      ),
    );

    expect(rows, {
      '播放内核': 'Media3',
      '选择原因': 'Android 优先使用 Media3',
      '视频解码': 'c2.qti.hevc.decoder',
      '动态范围': '杜比视界 Profile 5',
      'HDR 送显': '是（HDR10）',
      '视频编码': 'HEVC',
      '杜比视界处理': 'GPU 重建为 HDR10',
    });
    expect(rows.keys, [
      '播放内核',
      '选择原因',
      '视频解码',
      '动态范围',
      'HDR 送显',
      '杜比视界处理',
      '视频编码',
    ]);
  });

  test('details follow a fixed order and keep unknown keys last', () {
    final rows = buildMediaInfoRows(
      engine: PlaybackEngineKind.aether,
      engineReason: '',
      videoInfo: const VideoInfo(),
      diagnostics: const MediaDiagnostics(
        details: {
          '字幕': 'libass',
          '自定义': 'x',
          '帧率': '24.00 fps',
          '视频编码': 'hevc',
        },
      ),
    );

    expect(rows.keys, ['播放内核', '视频编码', '帧率', '字幕', '自定义']);
  });

  test('hdr source shown as sdr is reported as mapped', () {
    final rows = buildMediaInfoRows(
      engine: PlaybackEngineKind.mpvTexture,
      engineReason: '',
      videoInfo: const VideoInfo(dynamicRange: VideoDynamicRange.hdr10),
      diagnostics: const MediaDiagnostics(
        videoDecoder: '软解',
        outputDynamicRange: VideoDynamicRange.sdr,
      ),
    );

    expect(rows, {
      '播放内核': 'mpv',
      '视频解码': '软解',
      '动态范围': 'HDR10',
      'HDR 送显': '否（已映射为 SDR）',
    });
  });

  test('unknown values are omitted', () {
    final rows = buildMediaInfoRows(
      engine: PlaybackEngineKind.aether,
      engineReason: 'Apple 平台使用 AetherEngine',
      videoInfo: const VideoInfo(),
      diagnostics: const MediaDiagnostics(),
    );

    expect(rows, {'播放内核': 'AetherEngine', '选择原因': 'Apple 平台使用 AetherEngine'});
  });

  test('sdr source on sdr output', () {
    final rows = buildMediaInfoRows(
      engine: PlaybackEngineKind.aether,
      engineReason: '',
      videoInfo: const VideoInfo(dynamicRange: VideoDynamicRange.sdr),
      diagnostics: const MediaDiagnostics(
        outputDynamicRange: VideoDynamicRange.sdr,
      ),
    );

    expect(rows['HDR 送显'], '否');
  });
}
