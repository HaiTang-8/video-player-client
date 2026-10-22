import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:native_player/native_player.dart';

/// 样片的 HTTP 地址前缀，通过 --dart-define 传入；未传时全部跳过。测试时用
/// `adb reverse` 把手机的端口转到电脑上的静态文件服务（需要支持 Range），目录中需要：
/// hdr10.mkv（HDR10，音轨 chi，SRT“简体”）、subs.mkv（另有 ASS“特效”）、styled.ass、
/// pgs.mkv（PGS“简体中字”，6 秒起）、test.mkv（杜比视界 P5，封装没有声明）、dv_p5_dvcc.mkv
/// （封装带 dvcC 的杜比视界 P5），以及 dts.mkv、ac3.mkv、eac3.mkv、truehd.mkv（对应编码的音频）
const _samples = String.fromEnvironment('NATIVE_PLAYER_ANDROID_SAMPLES');

/// 为 true 时在关键画面打印 NP_HOLD 标记并停留，方便截图核对
const _hold = bool.fromEnvironment('NATIVE_PLAYER_HOLD');

class _Recorder implements NativePlayerEventsApi {
  int durationMs = 0;
  int positionMs = 0;
  bool playing = false;
  double? rate;
  double? volume;
  List<NativeTrack> audio = [];
  List<NativeTrack> subtitle = [];
  String? selectedSubtitle;
  NativeVideoInfo? videoInfo;
  final List<NativeError> errors = [];

  @override
  void onPosition(int playerId, int positionMs) => this.positionMs = positionMs;
  @override
  void onDuration(int playerId, int durationMs) => this.durationMs = durationMs;
  @override
  void onPlaying(int playerId, bool playing) => this.playing = playing;
  @override
  void onBuffering(int playerId, bool buffering) {}
  @override
  void onCompleted(int playerId, bool completed) {}
  @override
  void onRate(int playerId, double rate) => this.rate = rate;
  @override
  void onVolume(int playerId, double volume) => this.volume = volume;
  @override
  void onTracks(
    int playerId,
    List<NativeTrack> audio,
    List<NativeTrack> subtitle,
  ) {
    this.audio = audio;
    this.subtitle = subtitle;
  }

  @override
  void onSelectedTracks(
    int playerId,
    String? audioTrackId,
    String? subtitleTrackId,
    bool subtitleOff,
  ) => selectedSubtitle = subtitleTrackId;
  @override
  void onVideoInfo(int playerId, NativeVideoInfo info) => videoInfo = info;
  @override
  void onError(int playerId, NativeError error) => errors.add(error);
}

Future<void> _waitFor(
  WidgetTester tester,
  bool Function() condition,
  String what,
) async {
  for (var i = 0; i < 200; i++) {
    if (condition()) return;
    await tester.pump(const Duration(milliseconds: 100));
  }
  fail('timed out waiting for $what');
}

Future<void> _holdForScreenshot(WidgetTester tester, String label) async {
  if (!_hold) return;
  debugPrint('NP_HOLD $label');
  for (var i = 0; i < 60; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await tester.pump();
  }
}

Future<(NativePlayerHostApi, _Recorder, int)> _open(
  WidgetTester tester,
  String file,
) async {
  final api = NativePlayerHostApi();
  final recorder = _Recorder();
  final id = await api.create();
  NativePlayerEventDispatcher.instance.register(id, recorder);
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: NativeVideoView(
        playerId: id,
        fit: NativeVideoFit.contain,
        onFitChanged: (fit) => api.setVideoFit(id, fit),
      ),
    ),
  );
  await api.open(
    id,
    NativeSource(
      url: '$_samples/$file',
      httpHeaders: {'X-Test': 'native-player'},
      isLocalFile: false,
    ),
    true,
  );
  return (api, recorder, id);
}

Future<void> _close(
  WidgetTester tester,
  NativePlayerHostApi api,
  int id,
) async {
  await tester.pumpWidget(const SizedBox());
  NativePlayerEventDispatcher.instance.unregister(id);
  await api.dispose(id);
}

/// 在 Android 真机上验证 Media3 后端
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const skip = _samples == '';

  testWidgets('reports capabilities', (tester) async {
    final caps = await NativePlayerHostApi().capabilities();
    debugPrint('NP_CAPS dolbyVision=${caps.dolbyVisionColor}');
    expect(caps.maxVolume, 1.0);
    expect(caps.maxRate, 3.0);
  }, skip: skip);

  testWidgets('plays a local HDR10 file through Media3', (tester) async {
    final (api, recorder, id) = await _open(tester, 'hdr10.mkv');
    await _waitFor(tester, () => recorder.durationMs > 7000, 'duration');
    await _waitFor(tester, () => recorder.playing, 'playing');
    await _waitFor(tester, () => recorder.positionMs > 500, 'position');
    await _waitFor(
      tester,
      () => recorder.videoInfo?.dynamicRange == NativeDynamicRange.hdr10,
      'hdr10 info',
    );
    expect(recorder.audio, isNotEmpty);
    expect(recorder.subtitle.single.title, '简体');

    await api.setRate(id, 2.0);
    await _waitFor(tester, () => recorder.rate == 2.0, 'rate');
    await api.setVolume(id, 0.5);
    await _waitFor(tester, () => recorder.volume == 0.5, 'volume');
    await api.seek(id, 5000);
    await _waitFor(tester, () => recorder.positionMs >= 4500, 'seek');

    final info = await api.diagnostics(id);
    debugPrint('NP_DIAG $info');
    expect(info.videoDecoder, isNotNull);
    if (info.details['屏幕 HDR'] != '不支持') {
      expect(info.outputDynamicRange, NativeDynamicRange.hdr10);
    }
    expect(recorder.errors, isEmpty);
    await _close(tester, api, id);
  }, skip: skip);

  testWidgets('renders embedded and external subtitles', (tester) async {
    final (api, recorder, id) = await _open(tester, 'subs.mkv');
    await _waitFor(tester, () => recorder.subtitle.length == 2, 'tracks');
    String trackId(String title) =>
        recorder.subtitle.firstWhere((t) => t.title == title).id;

    await api.selectSubtitleTrack(id, trackId('特效'));
    await _waitFor(
      tester,
      () => recorder.selectedSubtitle == trackId('特效'),
      'ass selected',
    );
    await _waitFor(tester, () => recorder.positionMs > 2000, 'playback');
    await api.pause(id);
    await _holdForScreenshot(tester, 'ass');

    await api.selectSubtitleTrack(id, trackId('简体'));
    await _waitFor(
      tester,
      () => recorder.selectedSubtitle == trackId('简体'),
      'srt selected',
    );
    await _holdForScreenshot(tester, 'srt');

    await api.selectSubtitleTrack(id, null);
    await _waitFor(tester, () => recorder.selectedSubtitle == null, 'off');

    await api.addExternalSubtitle(id, _externalAss, '外挂特效', 'ass');
    await _waitFor(
      tester,
      () => recorder.subtitle.any((t) => t.title == '外挂特效'),
      'external track',
    );
    await _waitFor(
      tester,
      () => recorder.selectedSubtitle == trackId('外挂特效'),
      'external selected',
    );
    await api.play(id);
    await _waitFor(tester, () => recorder.positionMs > 2500, 'playback');
    await api.pause(id);
    await _holdForScreenshot(tester, 'external');
    expect(recorder.errors, isEmpty);
    await _close(tester, api, id);
  }, skip: skip);

  testWidgets('renders PGS bitmap subtitles', (tester) async {
    final (api, recorder, id) = await _open(tester, 'pgs.mkv');
    await _waitFor(tester, () => recorder.subtitle.isNotEmpty, 'tracks');
    await api.selectSubtitleTrack(id, recorder.subtitle.first.id);
    await _waitFor(tester, () => recorder.positionMs > 6600, 'playback');
    await api.pause(id);
    await _holdForScreenshot(tester, 'pgs');
    expect(recorder.errors, isEmpty);
    await _close(tester, api, id);
  }, skip: skip);

  testWidgets('plays Dolby Vision Profile 5 or asks for fallback', (
    tester,
  ) async {
    final caps = await NativePlayerHostApi().capabilities();
    final (api, recorder, id) = await _open(tester, 'test.mkv');
    await _waitFor(
      tester,
      () => recorder.videoInfo?.dynamicRange == NativeDynamicRange.dolbyVision,
      'dolby vision info',
    );
    expect(recorder.videoInfo?.dolbyVisionProfile, 5);
    if (caps.dolbyVisionColor) {
      await _waitFor(tester, () => recorder.positionMs > 3000, 'playback');
      final info = await api.diagnostics(id);
      debugPrint('NP_DIAG $info');
      await _holdForScreenshot(tester, 'dv');
      expect(recorder.errors, isEmpty);
      _expectGpuReshapingWithoutDecoder(info);
    } else {
      await _waitFor(tester, () => recorder.errors.isNotEmpty, 'fallback');
      expect(recorder.errors.single.fallbackSuggested, isTrue);
    }
    await _close(tester, api, id);
  }, skip: skip);

  testWidgets('plays Dolby Vision P5 declared in the container', (
    tester,
  ) async {
    final caps = await NativePlayerHostApi().capabilities();
    final (api, recorder, id) = await _open(tester, 'dv_p5_dvcc.mkv');
    await _waitFor(
      tester,
      () => recorder.videoInfo?.dynamicRange == NativeDynamicRange.dolbyVision,
      'dolby vision info',
    );
    expect(recorder.videoInfo?.dolbyVisionProfile, 5);
    if (caps.dolbyVisionColor) {
      await _waitFor(tester, () => recorder.positionMs > 3000, 'playback');
      await api.seek(id, 1000);
      await _waitFor(
        tester,
        () => recorder.positionMs > 2500,
        'playback after seek',
      );
      final info = await api.diagnostics(id);
      debugPrint('NP_DIAG_DVCC $info');
      expect(recorder.errors, isEmpty);
      expect(info.details['视频编码'], startsWith('Dolby Vision (dvhe.05'));
      _expectGpuReshapingWithoutDecoder(info);
    } else {
      await _waitFor(tester, () => recorder.errors.isNotEmpty, 'fallback');
      expect(recorder.errors.single.fallbackSuggested, isTrue);
    }
    await _close(tester, api, id);
  }, skip: skip);

  testWidgets('decodes AC3 / E-AC3 / DTS / TrueHD without fallback', (
    tester,
  ) async {
    final decoders = <String, String>{};
    for (final file in ['ac3.mkv', 'eac3.mkv', 'dts.mkv', 'truehd.mkv']) {
      final (api, recorder, id) = await _open(tester, file);
      await _waitFor(
        tester,
        () => recorder.errors.isNotEmpty || recorder.positionMs > 2000,
        '$file playback',
      );
      final info = await api.diagnostics(id);
      debugPrint(
        'NP_AUDIO $file errors=${recorder.errors.map((e) => e.message)} $info',
      );
      expect(recorder.errors, isEmpty, reason: file);
      decoders[file] = info.details['音频解码']!;
      await _close(tester, api, id);
    }
    // 系统有对应解码器时优先使用系统的，手机上至少 DTS / TrueHD 会走 FFmpeg
    expect(
      decoders.values.any((name) => name.startsWith('ffmpeg')),
      isTrue,
      reason: '$decoders',
    );
  }, skip: skip);
}

const _externalAss = r'''[Script Info]
ScriptType: v4.00+
PlayResX: 1920
PlayResY: 1080

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Default,Sans,80,&H00FFFFFF,&H0000FFFF,&H00000000,&H80000000,0,0,0,0,100,100,0,0,1,4,1,2,60,60,60,1
Style: Top,Sans,70,&H0000FFFF,&H000000FF,&H00000000,&H80000000,1,0,0,0,100,100,0,0,1,3,0,8,60,60,60,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
Dialogue: 0,0:00:00.20,0:00:07.80,Default,,0,0,0,,{\c&H0000FF&\i1}外挂红色斜体字幕
Dialogue: 0,0:00:00.20,0:00:07.80,Top,,0,0,0,,外挂顶部黄色样式
''';

/// 没有杜比视界解码器时 P5 应由 GPU 重建为 HDR10
void _expectGpuReshapingWithoutDecoder(NativeDiagnostics info) {
  final details = info.details;
  if (details['杜比视界解码器'] != '无') return;
  expect(details['杜比视界处理'], 'GPU 重建为 HDR10');
  expect(details['HDR10 元数据'], startsWith('母版'));
  if (details['屏幕 HDR'] != '不支持') {
    expect(info.outputDynamicRange, NativeDynamicRange.hdr10);
  }
}
