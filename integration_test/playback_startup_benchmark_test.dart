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
const _targetSeconds = int.fromEnvironment(
  'BENCH_TARGET_SECONDS',
  defaultValue: 600,
);
const _runs = int.fromEnvironment('BENCH_RUNS', defaultValue: 2);

/// 只跑指定场景（`lan` / `netdisk`），为空时全部运行
const _onlyScenario = String.fromEnvironment('BENCH_SCENARIO');

/// 为 true 时网络片源经过本机代理（Stage 2）
const _viaProxy = bool.fromEnvironment('BENCH_PROXY');

class _Scenario {
  const _Scenario(
    this.name, {
    required this.latency,
    this.bytesPerSecond,
    this.redirect = false,
  });

  final String name;

  /// 同时作用于流地址 API 和源站的每个请求
  final Duration latency;
  final int? bytesPerSecond;
  final bool redirect;
}

const _scenarios = [
  _Scenario('lan', latency: Duration(milliseconds: 5)),
  _Scenario(
    'netdisk',
    latency: Duration(milliseconds: 300),
    bytesPerSecond: 6 * 1024 * 1024,
    redirect: true,
  ),
];

class _DelayedSourceGateway extends FakeSourceGateway {
  _DelayedSourceGateway(this.latency);

  final Duration latency;

  @override
  Future<StreamInfo?> fetchStreamInfo(PlaybackItem item) async {
    await Future<void>.delayed(latency);
    return super.fetchStreamInfo(item);
  }
}

String _describe(PlaybackSessionStatus status) =>
    status is PlaybackSessionFailed ? status.message : '$status';

Future<void> _waitFor(
  WidgetTester tester,
  bool Function() condition,
  String what,
) async {
  for (var i = 0; i < 600; i++) {
    if (condition()) return;
    await tester.pump(const Duration(milliseconds: 100));
  }
  fail('timed out waiting for $what');
}

/// 起播耗时基准：本机 Range 源站模拟局域网服务器与网盘直链，分别测从头播放和续播
///
/// 结果以 `NP_BENCH` 开头的行输出，对应 doc/playback_cache_plan.md Stage 0.3
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('startup benchmark', (tester) async {
    final server = await RangeTestServer.start(
      File(_samplePath),
      contentType:
          _samplePath.toLowerCase().endsWith('.mp4')
              ? 'video/mp4'
              : 'video/x-matroska',
    );
    addTearDown(server.close);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final proxy = PlaybackProxy();

    for (final scenario in _scenarios) {
      if (_onlyScenario.isNotEmpty && scenario.name != _onlyScenario) continue;
      server
        ..firstByteLatency = scenario.latency
        ..bytesPerSecond = scenario.bytesPerSecond;
      for (final target in [null, const Duration(seconds: _targetSeconds)]) {
        for (var run = 1; run <= _runs; run++) {
          final uri = scenario.redirect ? server.redirectUri : server.mediaUri;
          final gateway = _DelayedSourceGateway(scenario.latency)
            ..streamInfo = StreamInfo(url: '$uri?run=$run');
          final session = PlaybackSession(
            selector: container.read(engineSelectorProvider),
            factory: container.read(playbackEngineFactoryProvider),
            environment: container.read(platformEnvironmentProvider),
            resolver:
                _viaProxy
                    ? ProxiedSourceResolver(
                      PlaybackSourceResolver(gateway),
                      proxy,
                    )
                    : PlaybackSourceResolver(gateway),
            sourceGateway: gateway,
            progressGateway: FakeProgressGateway(),
            defaultRate: () => 1.0,
          );
          await session.initialize();
          server.resetStats();

          await session.load(const MoviePlaybackItem(1), startAt: target);
          expect(
            session.status,
            isA<PlaybackSessionReady>(),
            reason: '${scenario.name}: ${_describe(session.status)}',
          );
          await tester.pumpWidget(
            Directionality(
              textDirection: TextDirection.ltr,
              child: Builder(
                builder:
                    (context) => session.engine.buildVideoView(
                      context,
                      fit: BoxFit.contain,
                    ),
              ),
            ),
          );
          await _waitFor(
            tester,
            () =>
                session.lastStartup != null ||
                session.status is PlaybackSessionFailed,
            '${scenario.name} startup',
          );
          expect(
            session.status,
            isNot(isA<PlaybackSessionFailed>()),
            reason: '${scenario.name}: ${_describe(session.status)}',
          );
          debugPrint(
            'NP_BENCH scenario=${scenario.name} run=$run '
            '${session.lastStartup} requests=${server.requestCount} '
            'served=${server.bytesServed ~/ (1024 * 1024)}MiB'
            '${_viaProxy ? ' proxy=${await proxy.stats()}' : ''}',
          );
          debugPrint('NP_BENCH_REQUESTS ${server.requestLog.join(' | ')}');
          debugPrint('NP_BENCH_TIMELINE ${server.timeline.join(' | ')}');

          await session.prepareExit();
          await tester.pumpWidget(const SizedBox());
          session.dispose();
          await tester.pump(const Duration(milliseconds: 500));
        }
      }
    }
  }, skip: _samplePath.isEmpty);
}
