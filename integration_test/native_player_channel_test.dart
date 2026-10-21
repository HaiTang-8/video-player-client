import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_player/playback/playback_providers.dart';
import 'package:native_player/native_player.dart';

/// 本地样片路径，通过 --dart-define 传入；未传时对应用例跳过
const _samplePath = String.fromEnvironment('NATIVE_PLAYER_SAMPLE');

/// 带内嵌 SRT（标题“简体”）和 ASS（标题“特效”）字幕的样片
const _subtitleSamplePath = String.fromEnvironment(
  'NATIVE_PLAYER_SUBTITLE_SAMPLE',
);

/// 外挂 ASS 字幕文件，配合 [_subtitleSamplePath] 使用
const _externalASSPath = String.fromEnvironment('NATIVE_PLAYER_EXTERNAL_ASS');

/// 带 PGS 字幕（标题“简体中字”）的样片，字幕从 6 秒开始
const _pgsSamplePath = String.fromEnvironment('NATIVE_PLAYER_PGS_SAMPLE');

/// 为 true 时在关键画面打印 NP_HOLD 标记并停留，方便在宿主侧截图核对
const _hold = bool.fromEnvironment('NATIVE_PLAYER_HOLD');

class _Recorder implements NativePlayerEventsApi {
  int durationMs = 0;
  int positionMs = 0;
  bool playing = false;
  double? rate;
  double? volume;
  List<NativeTrack> audio = [];
  List<NativeTrack> subtitle = [];
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
  ) {}
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

Future<void> _waitForSubtitle(
  WidgetTester tester,
  NativePlayerHostApi api,
  int id,
  String expected,
) async {
  String? current;
  for (var i = 0; i < 100; i++) {
    current = (await api.diagnostics(id))['字幕'];
    if (current == expected) return;
    await tester.pump(const Duration(milliseconds: 100));
  }
  fail('subtitle renderer is $current, expected $expected');
}

Future<(NativePlayerHostApi, _Recorder, int)> _openSample(
  WidgetTester tester,
  String path,
) async {
  final api = NativePlayerHostApi();
  final recorder = _Recorder();
  await api.configureSubtitleFonts(subtitleFontAssets);
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
    NativeSource(url: path, httpHeaders: {}, isLocalFile: true),
    true,
  );
  await _waitFor(tester, () => recorder.subtitle.isNotEmpty, 'subtitle tracks');
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

/// 在真实宿主上验证 Pigeon 通道、PlatformView 与 AetherEngine 播放
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('channel errors and lifecycle', (tester) async {
    final api = NativePlayerHostApi();
    final caps = await api.capabilities();
    expect(caps.dolbyVisionColor, isTrue);
    expect(caps.maxRate, 2.0);

    final id = await api.create();
    await expectLater(
      api.open(
        id,
        NativeSource(
          url: '/nonexistent/sample.mkv',
          httpHeaders: {},
          isLocalFile: true,
        ),
        true,
      ),
      throwsA(isA<PlatformException>()),
    );
    await api.dispose(id);
    await expectLater(
      api.play(id),
      throwsA(
        isA<PlatformException>().having(
          (e) => e.code,
          'code',
          'unknown_player',
        ),
      ),
    );
  });

  testWidgets('plays a local HDR10 file through AetherEngine', (tester) async {
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
      NativeSource(url: _samplePath, httpHeaders: {}, isLocalFile: true),
      true,
    );

    await _waitFor(tester, () => recorder.durationMs > 7000, 'duration');
    await _waitFor(tester, () => recorder.playing, 'playing');
    await _waitFor(tester, () => recorder.positionMs > 500, 'position');
    await _waitFor(
      tester,
      () => recorder.videoInfo?.dynamicRange == NativeDynamicRange.hdr10,
      'hdr10 video info',
    );
    await _waitFor(tester, () => recorder.audio.isNotEmpty, 'tracks');
    expect(recorder.audio.single.language, 'chi');
    expect(recorder.subtitle.single.title, '简体');

    await api.seek(id, 5000);
    await _waitFor(tester, () => recorder.positionMs >= 4500, 'seek');

    await api.setRate(id, 3.0);
    expect(recorder.rate, 2.0);
    await api.setVolume(id, 0.5);
    expect(recorder.volume, 0.5);

    final info = await api.diagnostics(id);
    expect(info['视频编码'], isNotNull);
    expect(recorder.errors, isEmpty);

    await tester.pumpWidget(const SizedBox());
    NativePlayerEventDispatcher.instance.unregister(id);
    await api.dispose(id);
  }, skip: _samplePath.isEmpty);

  testWidgets(
    'renders ASS and SRT subtitles through libass',
    (tester) async {
      final (api, recorder, id) = await _openSample(
        tester,
        _subtitleSamplePath,
      );
      String trackId(String title) =>
          recorder.subtitle.firstWhere((t) => t.title == title).id;

      // 与实际用法一致：开播时选中字幕，播放一段后暂停
      await api.selectSubtitleTrack(id, trackId('特效'));
      await _waitForSubtitle(tester, api, id, 'ASS（libass）');
      await _waitFor(tester, () => recorder.positionMs > 2000, 'playback');
      await api.pause(id);
      await _holdForScreenshot(tester, 'ass');

      await api.selectSubtitleTrack(id, trackId('简体'));
      await _waitForSubtitle(tester, api, id, 'SRT（libass）');
      await _holdForScreenshot(tester, 'srt');

      await api.selectSubtitleTrack(id, null);
      await _waitForSubtitle(tester, api, id, '关闭');
      expect(recorder.errors, isEmpty);
      await _close(tester, api, id);
    },
    skip: _subtitleSamplePath.isEmpty,
  );

  testWidgets(
    'renders external ASS subtitles through libass',
    (tester) async {
      final (api, recorder, id) = await _openSample(
        tester,
        _subtitleSamplePath,
      );
      final text = await File(_externalASSPath).readAsString();

      await api.addExternalSubtitle(id, text, '外挂特效', 'ass');
      await _waitForSubtitle(tester, api, id, 'ASS（libass）');
      await _waitFor(tester, () => recorder.positionMs > 2000, 'playback');
      await api.pause(id);
      await _holdForScreenshot(tester, 'external');
      expect(recorder.errors, isEmpty);
      await _close(tester, api, id);
    },
    skip: _subtitleSamplePath.isEmpty || _externalASSPath.isEmpty,
  );

  testWidgets('renders PGS bitmap subtitles', (tester) async {
    final (api, recorder, id) = await _openSample(tester, _pgsSamplePath);
    final track = recorder.subtitle.firstWhere((t) => t.title == '简体中字');

    await api.selectSubtitleTrack(id, track.id);
    await _waitForSubtitle(tester, api, id, 'PGS（位图）');
    await _waitFor(tester, () => recorder.positionMs > 6600, 'playback');
    await api.pause(id);
    await _holdForScreenshot(tester, 'pgs');
    await _close(tester, api, id);
  }, skip: _pgsSamplePath.isEmpty);
}
