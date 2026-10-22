import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_player/data/models/stream_info.dart';
import 'package:media_player/playback/cache/playback_proxy.dart';
import 'package:media_player/playback/cache/proxied_source_resolver.dart';
import 'package:media_player/playback/playback_providers.dart';
import 'package:media_player/playback/session/playback_item.dart';
import 'package:media_player/playback/session/playback_session.dart';
import 'package:media_player/playback/session/playback_source_resolver.dart';

import '../test/playback/cache/support/range_test_server.dart';
import '../test/playback/fakes/fake_gateways.dart';

const _samplePath = String.fromEnvironment('NATIVE_PLAYER_SAMPLE');

/// 为 true 时暂停后打印 NP_PROXY_BACKGROUND_NOW，等宿主把 App 切到后台再切回来
const _backgroundCheck = bool.fromEnvironment('PROXY_BACKGROUND_CHECK');

class _LifecycleLog with WidgetsBindingObserver {
  final List<AppLifecycleState> states = [];

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => states.add(state);
}

Future<void> _waitFor(
  WidgetTester tester,
  bool Function() condition,
  String what, {
  int seconds = 30,
}) async {
  for (var i = 0; i < seconds * 10; i++) {
    if (condition()) return;
    await tester.pump(const Duration(milliseconds: 100));
  }
  fail('timed out waiting for $what');
}

/// Stage 2：Aether 经本机代理播放网络片源（鉴权头、续播、seek、倍速、前后台重建）
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('aether plays a network source through the proxy', (
    tester,
  ) async {
    final server = await RangeTestServer.start(File(_samplePath));
    addTearDown(server.close);
    final gateway =
        FakeSourceGateway()
          ..serverUrl = 'http://127.0.0.1:${server.mediaUri.port}'
          ..streamInfo = StreamInfo(url: server.redirectUri.toString());
    // 与服务器同源时解析器会带上 Bearer token，代理必须把它转给上游（含 302 之后）
    server.requiredHeaders = const {'Authorization': 'Bearer token'};
    final proxy = PlaybackProxy();
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final session = PlaybackSession(
      selector: container.read(engineSelectorProvider),
      factory: container.read(playbackEngineFactoryProvider),
      environment: container.read(platformEnvironmentProvider),
      resolver: ProxiedSourceResolver(PlaybackSourceResolver(gateway), proxy),
      sourceGateway: gateway,
      progressGateway: FakeProgressGateway(),
      defaultRate: () => 1.0,
    );
    final lifecycle = _LifecycleLog();
    WidgetsBinding.instance.addObserver(lifecycle);
    addTearDown(() => WidgetsBinding.instance.removeObserver(lifecycle));

    await session.initialize();
    await session.load(
      const MoviePlaybackItem(1),
      startAt: const Duration(seconds: 120),
    );
    expect(session.status, isA<PlaybackSessionReady>());
    expect(session.currentUrl, startsWith('http://127.0.0.1:'));
    final engine = session.engine;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Builder(
          builder:
              (context) => engine.buildVideoView(context, fit: BoxFit.contain),
        ),
      ),
    );

    bool playingPast(int seconds) =>
        engine.state.playing &&
        engine.state.position > Duration(seconds: seconds);
    await _waitFor(
      tester,
      () => engine.state.firstFrameRendered,
      'first frame',
    );
    await _waitFor(tester, () => playingPast(121), 'resume at 120s');
    debugPrint('NP_PROXY startup ${session.lastStartup}');

    await session.seek(const Duration(seconds: 400));
    await _waitFor(tester, () => playingPast(401), 'seek forward');
    await session.seek(const Duration(seconds: 30));
    await _waitFor(
      tester,
      () =>
          playingPast(31) &&
          engine.state.position < const Duration(seconds: 60),
      'seek back',
    );

    await engine.setRate(1.5);
    await _waitFor(tester, () => engine.state.rate == 1.5, 'rate');

    if (_backgroundCheck) {
      await engine.pause();
      final before = (await proxy.stats())['requests']!;
      debugPrint('NP_PROXY_BACKGROUND_NOW');
      await _waitFor(
        tester,
        () => lifecycle.states.contains(AppLifecycleState.resumed),
        'background and resume',
        seconds: 120,
      );
      expect(lifecycle.states, contains(AppLifecycleState.paused));
      expect(await proxy.ensureListening(), isTrue);
      await tester.pump(const Duration(seconds: 2));
      await engine.play();
      final resumeAt = engine.state.position;
      await _waitFor(
        tester,
        () =>
            engine.state.playing &&
            engine.state.position > resumeAt + const Duration(seconds: 2),
        'playback after resume',
      );
      final stats = await proxy.stats();
      debugPrint('NP_PROXY after resume $stats lifecycle=${lifecycle.states}');
      expect(stats['requests']!, greaterThan(before), reason: '重建后经代理重新请求');
    }

    expect(session.status, isA<PlaybackSessionReady>());
    final stats = await proxy.stats();
    debugPrint('NP_PROXY stats $stats');
    debugPrint('NP_PROXY timeline ${server.timeline.join(' | ')}');
    expect(
      stats['cancelledUpstreams']!,
      greaterThan(0),
      reason: 'seek 放弃的请求应取消上游',
    );
    expect(server.requestLog.where((l) => l.startsWith('GET')), isNotEmpty);

    await session.prepareExit();
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  }, skip: _samplePath.isEmpty);
}
