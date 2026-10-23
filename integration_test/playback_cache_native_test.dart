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
import 'package:media_player/playback/session/playback_startup_timeline.dart';

import '../test/playback/cache/support/range_test_server.dart';
import '../test/playback/fakes/fake_gateways.dart';

const _samplePath = String.fromEnvironment('NATIVE_PLAYER_SAMPLE');

Future<void> _waitFor(
  WidgetTester tester,
  bool Function() condition,
  String what, {
  int seconds = 60,
}) async {
  for (var i = 0; i < seconds * 10; i++) {
    if (condition()) return;
    await tester.pump(const Duration(milliseconds: 100));
  }
  fail('timed out waiting for $what');
}

/// Stage 4：Aether 经缓存代理续播——冷启动、命中缓存的再次续播、seek 到未缓存区间、源站不可用时播放已缓存部分
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'resume hits the cache and survives the source going away',
    (tester) async {
      final server = await RangeTestServer.start(
        File(_samplePath),
        firstByteLatency: const Duration(milliseconds: 300),
        bytesPerSecond: 6 << 20,
        contentType:
            _samplePath.toLowerCase().endsWith('.mp4')
                ? 'video/mp4'
                : 'video/x-matroska',
      );
      var serverUp = true;
      addTearDown(() async {
        if (serverUp) await server.close();
      });
      server.requiredHeaders = const {'Authorization': 'Bearer token'};
      final gateway =
          FakeSourceGateway()
            ..serverUrl = 'http://127.0.0.1:${server.mediaUri.port}'
            ..streamInfo = StreamInfo(url: server.redirectUri.toString());
      final cacheDir = await Directory.systemTemp.createTemp('playback_cache');
      addTearDown(() => cacheDir.delete(recursive: true));
      final proxy = PlaybackProxy(cacheDirectory: () async => cacheDir);
      final container = ProviderContainer();
      addTearDown(container.dispose);

      Future<PlaybackStartupReport> play(
        String label,
        Duration startAt, {
        Duration playFor = const Duration(seconds: 4),
        Duration? seekTo,
      }) async {
        final session = PlaybackSession(
          selector: container.read(engineSelectorProvider),
          factory: container.read(playbackEngineFactoryProvider),
          environment: container.read(platformEnvironmentProvider),
          resolver: ProxiedSourceResolver(
            PlaybackSourceResolver(gateway),
            proxy,
            serverUrl: () => gateway.serverUrl,
          ),
          sourceGateway: gateway,
          progressGateway: FakeProgressGateway(),
          defaultRate: () => 1.0,
        );
        final before = await proxy.stats();
        final served = serverUp ? server.bytesServed : 0;
        await session.initialize();
        await session.load(const MoviePlaybackItem(1), startAt: startAt);
        expect(session.status, isA<PlaybackSessionReady>(), reason: label);
        final engine = session.engine;
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Builder(
              builder:
                  (context) =>
                      engine.buildVideoView(context, fit: BoxFit.contain),
            ),
          ),
        );
        await _waitFor(
          tester,
          () => session.lastStartup != null,
          '$label startup',
        );
        final report = session.lastStartup!;
        final startupServed = (serverUp ? server.bytesServed : 0) - served;
        final startupStats = await proxy.stats();
        await _waitFor(
          tester,
          () =>
              engine.state.playing && engine.state.position > startAt + playFor,
          '$label playback',
        );
        if (seekTo != null) {
          await session.seek(seekTo);
          await _waitFor(
            tester,
            () =>
                engine.state.playing &&
                engine.state.position > seekTo + const Duration(seconds: 2) &&
                engine.state.position < seekTo + const Duration(seconds: 30),
            '$label seek',
          );
        }
        expect(session.status, isA<PlaybackSessionReady>(), reason: label);
        debugPrint(
          'NP_CACHE $label $report sourceBytesDuringStartup='
          '${startupServed ~/ 1024}KiB '
          'cacheBytes=${(startupStats['cacheBytes']! - before['cacheBytes']!) ~/ 1024}KiB '
          'upstreamBytes=${(startupStats['upstreamBytes']! - before['upstreamBytes']!) ~/ 1024}KiB',
        );
        await session.prepareExit();
        await tester.pumpWidget(const SizedBox());
        session.dispose();
        await tester.pump(const Duration(milliseconds: 500));
        await proxy.flush();
        return report;
      }

      final cold = await play('cold', const Duration(seconds: 400));
      final warm = await play(
        'warm',
        const Duration(seconds: 404),
        seekTo: const Duration(seconds: 100),
      );
      debugPrint('NP_CACHE usage ${await proxy.usage()}');

      await server.close();
      serverUp = false;
      final offline = await play(
        'offline',
        const Duration(seconds: 405),
        playFor: const Duration(seconds: 2),
      );

      expect(warm.firstFrame!, lessThan(cold.firstFrame!));
      expect(offline.firstFrame, isNotNull);
      debugPrint('NP_CACHE stats ${await proxy.stats()}');
    },
    skip: _samplePath.isEmpty,
  );
}
