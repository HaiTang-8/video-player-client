import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/playback/domain/playback_domain.dart';
import 'package:media_player/playback/engines/native/native_playback_engine.dart';
import 'package:native_player/native_player.dart';

class _FakeHostApi extends NativePlayerHostApi {
  final List<String> calls = [];
  NativeSource? opened;

  @override
  Future<NativeCapabilities> capabilities() async =>
      NativeCapabilities(dolbyVisionColor: true, maxVolume: 1.0, maxRate: 2.0);

  @override
  Future<void> configureSubtitleFonts(List<String> assetKeys) async =>
      calls.add('fonts ${assetKeys.join(',')}');

  @override
  Future<int> create() async {
    calls.add('create');
    return 7;
  }

  @override
  Future<void> open(int playerId, NativeSource source, bool autoPlay) async {
    opened = source;
    calls.add('open $playerId ${source.url} $autoPlay');
  }

  @override
  Future<void> play(int playerId) async => calls.add('play $playerId');

  @override
  Future<void> pause(int playerId) async => calls.add('pause $playerId');

  @override
  Future<void> seek(int playerId, int positionMs) async =>
      calls.add('seek $playerId $positionMs');

  @override
  Future<void> setRate(int playerId, double rate) async =>
      calls.add('rate $rate');

  @override
  Future<void> setVolume(int playerId, double volume) async =>
      calls.add('volume $volume');

  @override
  Future<void> selectAudioTrack(int playerId, String trackId) async =>
      calls.add('audio $trackId');

  @override
  Future<void> selectSubtitleTrack(int playerId, String? trackId) async =>
      calls.add('subtitle $trackId');

  @override
  Future<void> addExternalSubtitle(
    int playerId,
    String text,
    String title,
    String? formatHint,
  ) async => calls.add('external $title $formatHint');

  @override
  Future<void> setVideoFit(int playerId, NativeVideoFit fit) async =>
      calls.add('fit ${fit.name}');

  @override
  Future<NativeDiagnostics> diagnostics(int playerId) async =>
      NativeDiagnostics(
        videoDecoder: 'c2.qti.hevc.decoder',
        outputDynamicRange: NativeDynamicRange.hdr10,
        details: {'视频编码': 'hevc'},
      );

  @override
  Future<void> dispose(int playerId) async => calls.add('dispose $playerId');
}

class _FakeRegistry implements NativePlayerEventRegistry {
  final Map<int, NativePlayerEventsApi> listeners = {};

  @override
  void register(int playerId, NativePlayerEventsApi listener) =>
      listeners[playerId] = listener;

  @override
  void unregister(int playerId) => listeners.remove(playerId);
}

void main() {
  late _FakeHostApi api;
  late _FakeRegistry registry;
  late NativePlaybackEngine engine;

  setUp(() {
    api = _FakeHostApi();
    registry = _FakeRegistry();
    engine = NativePlaybackEngine(
      kind: PlaybackEngineKind.aether,
      initialCapabilities: const EngineCapabilities(
        dolbyVisionColor: false,
        maxVolume: 1.0,
        maxRate: 1.0,
      ),
      subtitleFontAssets: const ['fonts/a.ttf', 'fonts/b.ttf'],
      api: api,
      events: registry,
    );
  });

  test(
    'initialize creates a native player and registers for its events',
    () async {
      expect(() => engine.play(), throwsStateError);
      await engine.initialize();

      expect(registry.listeners[7], same(engine));
      expect(engine.capabilities.dolbyVisionColor, isTrue);
      expect(engine.capabilities.maxRate, 2.0);
    },
  );

  test('forwards transport and track calls with the player id', () async {
    await engine.initialize();
    await engine.open(
      const PlaybackSource.network(
        'https://media.local/a.mkv',
        httpHeaders: {'Authorization': 'Bearer t'},
      ),
    );
    await engine.seek(const Duration(seconds: 90));
    await engine.setVolume(0.5);
    await engine.selectSubtitleTrack(null);
    await engine.addExternalSubtitle(
      const ExternalSubtitle.data('...', title: '中文', formatHint: 'ass'),
    );

    expect(api.opened!.httpHeaders, {'Authorization': 'Bearer t'});
    expect(api.opened!.isLocalFile, isFalse);
    expect(api.opened!.startPositionMs, isNull);
    expect(api.calls, [
      'fonts fonts/a.ttf,fonts/b.ttf',
      'create',
      'open 7 https://media.local/a.mkv true',
      'seek 7 90000',
      'volume 0.5',
      'subtitle null',
      'external 中文 ass',
    ]);
    final diagnostics = await engine.fetchDiagnostics();
    expect(diagnostics.videoDecoder, 'c2.qti.hevc.decoder');
    expect(diagnostics.outputDynamicRange, VideoDynamicRange.hdr10);
    expect(diagnostics.details, {'视频编码': 'hevc'});
  });

  test('forwards the start position in milliseconds', () async {
    await engine.initialize();
    await engine.open(
      const PlaybackSource.localFile('/movies/a.mkv'),
      startPosition: const Duration(minutes: 6, milliseconds: 40),
    );
    expect(api.opened!.startPositionMs, 360040);
  });

  test('maps native events into the playback state', () async {
    await engine.initialize();
    engine
      ..onDuration(7, 5400000)
      ..onPosition(7, 1500)
      ..onPlaying(7, true)
      ..onTracks(
        7,
        [NativeTrack(id: 'a1', language: 'chi')],
        [NativeTrack(id: 's1', title: '简体', language: 'chi')],
      )
      ..onSelectedTracks(7, 'a1', null, true)
      ..onVideoInfo(
        7,
        NativeVideoInfo(
          dynamicRange: NativeDynamicRange.dolbyVision,
          dolbyVisionProfile: 5,
        ),
      );

    expect(engine.state.firstFrameRendered, isFalse);
    engine.onFirstFrame(7);

    final state = engine.state;
    expect(state.firstFrameRendered, isTrue);
    expect(state.duration, const Duration(minutes: 90));
    expect(state.position, const Duration(milliseconds: 1500));
    expect(state.playing, isTrue);
    expect(state.tracks.subtitle.single.title, '简体');
    expect(state.selectedTracks.audio?.language, 'chi');
    expect(state.selectedTracks.subtitleOff, isTrue);
    expect(
      state.videoInfo,
      const VideoInfo(
        dynamicRange: VideoDynamicRange.dolbyVision,
        dolbyVisionProfile: 5,
      ),
    );
  });

  test('maps native errors', () async {
    await engine.initialize();
    final errors = <PlaybackError>[];
    engine.streams.errors.listen(errors.add);
    engine.onError(
      7,
      NativeError(
        kind: NativeErrorKind.http,
        message: 'refused',
        httpStatus: 403,
        recoverable: false,
        fallbackSuggested: false,
      ),
    );
    engine.onError(
      7,
      NativeError(
        kind: NativeErrorKind.decoder,
        message: 'no decoder',
        recoverable: false,
        fallbackSuggested: true,
      ),
    );
    await pumpEventQueue();

    expect(errors.first.kind, PlaybackErrorKind.http);
    expect(errors.first.httpStatus, 403);
    expect(errors.first.fallbackSuggested, isFalse);
    expect(errors.last.fallbackSuggested, isTrue);
  });

  testWidgets('video view reports fit changes', (tester) async {
    await engine.initialize();
    Widget view(BoxFit fit) => Directionality(
      textDirection: TextDirection.ltr,
      child: Builder(
        builder: (context) => engine.buildVideoView(context, fit: fit),
      ),
    );
    await tester.pumpWidget(view(BoxFit.contain));
    await tester.pumpWidget(view(BoxFit.cover));

    expect(api.calls.last, 'fit cover');
  });

  test('dispose releases the native player once', () async {
    await engine.initialize();
    await engine.dispose();
    await engine.dispose();

    expect(registry.listeners, isEmpty);
    expect(api.calls.where((c) => c.startsWith('dispose')), ['dispose 7']);
  });

  test('dispose during initialize releases the late player', () async {
    final pending = engine.initialize();
    await engine.dispose();
    await pending;

    expect(registry.listeners, isEmpty);
    expect(api.calls, ['fonts fonts/a.ttf,fonts/b.ttf', 'create', 'dispose 7']);
  });
}
