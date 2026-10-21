import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_player/data/models/subtitle_info.dart';
import 'package:media_player/playback/domain/playback_domain.dart';
import 'package:media_player/playback/playback_providers.dart';
import 'package:media_player/playback/session/playback_item.dart';
import 'package:media_player/playback/session/playback_session.dart';
import 'package:media_player/playback/session/playback_source_resolver.dart';

import '../test/playback/fakes/fake_gateways.dart';

const _samplePath = String.fromEnvironment('NATIVE_PLAYER_SAMPLE');

/// Android：Media3 无法解码的样片地址（如 DTS 音频），验证会话自动回退到 mpv
const _fallbackUrl = String.fromEnvironment('NATIVE_PLAYER_FALLBACK_URL');

class _LocalResolver implements PlaybackSourceResolver {
  _LocalResolver([this.source = const PlaybackSource.localFile(_samplePath)]);

  final PlaybackSource source;

  @override
  Future<ResolvedPlayback> resolve(PlaybackItem item) async =>
      ResolvedPlayback(source);

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

  testWidgets(
    'session falls back from Media3 to mpv and keeps playing',
    (tester) async {
      MediaKit.ensureInitialized();
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final session = PlaybackSession(
        selector: container.read(engineSelectorProvider),
        factory: container.read(playbackEngineFactoryProvider),
        environment: container.read(platformEnvironmentProvider),
        resolver: _LocalResolver(const PlaybackSource.network(_fallbackUrl)),
        sourceGateway: FakeSourceGateway(),
        progressGateway: FakeProgressGateway(),
        defaultRate: () => 1.0,
      );
      final notices = <String>[];
      session.notices.listen(notices.add);
      expect(session.engine.kind, PlaybackEngineKind.media3);

      Widget view() => Directionality(
        textDirection: TextDirection.ltr,
        child: Builder(
          builder:
              (context) =>
                  session.engine.buildVideoView(context, fit: BoxFit.contain),
        ),
      );
      await session.initialize();
      await session.load(const MoviePlaybackItem(1));
      await tester.pumpWidget(view());

      await _waitFor(
        tester,
        () => session.engine.kind == PlaybackEngineKind.mpvTexture,
        'fallback to mpv',
      );
      await tester.pumpWidget(view());
      await _waitFor(
        tester,
        () => session.engine.state.position > const Duration(seconds: 2),
        'mpv playback',
      );
      debugPrint('NP_FALLBACK notices=$notices');
      expect(notices.any((n) => n.contains('已切换到 mpv')), isTrue);
      expect(session.status, isA<PlaybackSessionReady>());

      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
    skip: _fallbackUrl.isEmpty,
  );
}
