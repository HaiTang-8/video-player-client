import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_player/data/models/subtitle_info.dart';
import 'package:media_player/playback/domain/playback_domain.dart';
import 'package:media_player/playback/playback_providers.dart';
import 'package:media_player/playback/session/playback_item.dart';
import 'package:media_player/playback/session/playback_session.dart';
import 'package:media_player/playback/session/playback_source_resolver.dart';

import '../test/playback/fakes/fake_gateways.dart';

const _samplePath = String.fromEnvironment('NATIVE_PLAYER_SAMPLE');

class _LocalResolver implements PlaybackSourceResolver {
  @override
  Future<ResolvedPlayback> resolve(PlaybackItem item) async =>
      const ResolvedPlayback(PlaybackSource.localFile(_samplePath));

  @override
  Future<String?> fetchSubtitleText(SubtitleInfo subtitle) async => null;

  @override
  void dispose() {}
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

/// 会话层 + 内核选择 + 原生引擎的端到端验证（不依赖服务器）
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'session plays a local file with the platform engine',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final progress = FakeProgressGateway();
      final session = PlaybackSession(
        selector: container.read(engineSelectorProvider),
        factory: container.read(playbackEngineFactoryProvider),
        environment: container.read(platformEnvironmentProvider),
        resolver: _LocalResolver(),
        sourceGateway: FakeSourceGateway(),
        progressGateway: progress,
        defaultRate: () => 3.0,
      );
      final notices = <String>[];
      session.notices.listen(notices.add);
      final engine = session.engine;
      expect(engine.kind, PlaybackEngineKind.aether);

      await session.initialize();
      await session.load(
        const MoviePlaybackItem(1),
        startAt: const Duration(seconds: 3),
      );
      expect(session.status, isA<PlaybackSessionReady>());

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
        () => engine.state.position >= const Duration(seconds: 3),
        'start position',
      );
      expect(engine.state.rate, 2.0);
      expect(engine.state.videoInfo.dynamicRange, VideoDynamicRange.hdr10);
      await _waitFor(
        tester,
        () => engine.state.selectedTracks.subtitle != null,
        'embedded chinese subtitle',
      );
      expect(engine.state.selectedTracks.subtitle!.title, '简体');
      expect(notices, contains('正在使用本地缓存播放'));

      await session.prepareExit();
      expect(engine.state.playing, isFalse);
      expect(progress.uploads, isNotEmpty);

      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
    skip: _samplePath.isEmpty,
  );
}
