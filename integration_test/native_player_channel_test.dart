import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:native_player/native_player.dart';

/// 本地媒体文件路径，通过 --dart-define=NATIVE_PLAYER_SAMPLE=... 传入
const _samplePath = String.fromEnvironment('NATIVE_PLAYER_SAMPLE');

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
}
