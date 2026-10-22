import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/data/models/subtitle_info.dart';
import 'package:media_player/playback/domain/playback_domain.dart';
import 'package:media_player/playback/engines/playback_engine_factory.dart';
import 'package:media_player/playback/selection/engine_selection_rule.dart';
import 'package:media_player/playback/selection/engine_selector.dart';
import 'package:media_player/playback/selection/platform_environment.dart';
import 'package:media_player/playback/session/playback_item.dart';
import 'package:media_player/playback/session/playback_session.dart';
import 'package:media_player/playback/session/playback_source_resolver.dart';

import '../fakes/fake_gateways.dart';
import '../fakes/fake_playback_engine.dart';

class _FakeResolver implements PlaybackSourceResolver {
  ResolvedPlayback? result;
  Object? error;
  int resolveCount = 0;
  bool disposed = false;

  @override
  Future<ResolvedPlayback> resolve(PlaybackItem item) async {
    resolveCount++;
    final failure = error;
    if (failure != null) throw failure;
    return result!;
  }

  @override
  Future<String?> fetchSubtitleText(SubtitleInfo subtitle) async =>
      'subtitle of ${subtitle.name}';

  @override
  void dispose() => disposed = true;
}

void main() {
  const movie = MoviePlaybackItem(1);
  const hour = Duration(hours: 1);
  late FakePlaybackEngine engine;
  late _FakeResolver resolver;
  late FakeSourceGateway sourceGateway;
  late FakeProgressGateway progressGateway;
  late PlaybackSession session;
  late List<String> notices;
  late List<Type> statuses;

  setUp(() {
    engine = FakePlaybackEngine();
    resolver =
        _FakeResolver()
          ..result = const ResolvedPlayback(
            PlaybackSource.network('http://media.local/a.mkv'),
            storageId: 1,
            filePath: '/movies/a.mkv',
          );
    sourceGateway = FakeSourceGateway();
    progressGateway = FakeProgressGateway();
    session = PlaybackSession(
      selector: const EngineSelector([DefaultMpvTextureRule()]),
      factory: PlaybackEngineFactory({
        PlaybackEngineKind.mpvTexture: () => engine,
      }),
      environment: const PlatformEnvironment(platform: TargetPlatform.macOS),
      resolver: resolver,
      sourceGateway: sourceGateway,
      progressGateway: progressGateway,
      defaultRate: () => 1.25,
    );
    notices = [];
    session.notices.listen(notices.add);
    statuses = [];
    session.addListener(() => statuses.add(session.status.runtimeType));
  });

  tearDown(() => session.dispose());

  test('loads source and becomes ready', () async {
    await session.load(movie);

    expect(statuses.take(3), [
      PlaybackSessionLoading,
      PlaybackSessionLoading,
      PlaybackSessionReady,
    ]);
    expect(engine.calls, ['open http://media.local/a.mkv']);
    expect(session.currentUrl, 'http://media.local/a.mkv');
    expect(session.filePath, '/movies/a.mkv');
  });

  test('applies rate and start position once duration is known', () async {
    await session.load(movie, startAt: const Duration(seconds: 120));
    engine.hub.update(duration: hour);
    await pumpEventQueue();

    expect(engine.calls, [
      'open http://media.local/a.mkv',
      'rate 1.25',
      'seek 120',
    ]);
  });

  test('user rate overrides default rate on next load', () async {
    session.rememberRate(2.0);
    await session.load(movie);
    engine.hub.update(duration: hour);
    await pumpEventQueue();
    expect(engine.calls.last, 'rate 2.0');
  });

  test('rate is clamped to the engine maximum', () async {
    engine.capabilities = const EngineCapabilities(
      dolbyVisionColor: true,
      maxVolume: 1.0,
      maxRate: 2.0,
    );
    session.rememberRate(3.0);
    await session.load(movie);
    engine.hub.update(duration: hour);
    await pumpEventQueue();
    expect(engine.calls.last, 'rate 2.0');
  });

  test('external subtitle carries its file extension', () async {
    await session.selectExternalSubtitle(subtitleInfo('movie.chs.ASS', 90));
    expect(engine.lastExternalFormatHint, 'ass');
  });

  test('user seek cancels the pending start position', () async {
    await session.load(movie, startAt: const Duration(seconds: 120));
    await session.seek(const Duration(seconds: 5));
    engine.hub.update(duration: hour);
    await pumpEventQueue();
    expect(engine.calls.where((c) => c.startsWith('seek')), ['seek 5']);
  });

  test('reload after a failed load keeps the start position', () async {
    resolver.error = const PlaybackSourceUnavailable();
    await session.load(movie, startAt: const Duration(seconds: 90));
    expect(session.status, isA<PlaybackSessionFailed>());
    expect((session.status as PlaybackSessionFailed).message, '无法获取播放地址');

    resolver.error = null;
    await session.reload();
    engine.hub.update(duration: hour);
    await pumpEventQueue();
    expect(session.status, isA<PlaybackSessionReady>());
    expect(engine.calls.last, 'seek 90');
  });

  test('reopening the same media re-applies settings', () async {
    await session.load(movie);
    engine.hub.update(duration: hour);
    await pumpEventQueue();
    await session.load(movie, startAt: const Duration(seconds: 30));
    engine.hub.update(duration: hour);
    await pumpEventQueue();

    expect(engine.calls.where((c) => c.startsWith('rate')), hasLength(2));
    expect(engine.calls.last, 'seek 30');
  });

  test('open failure reports the url', () async {
    engine.openError = StateError('boom');
    await session.load(movie);
    final status = session.status as PlaybackSessionFailed;
    expect(status.message, contains('加载失败'));
    expect(status.message, contains('http://media.local/a.mkv'));
  });

  test(
    'fatal engine error fails the session, recoverable one does not',
    () async {
      await session.load(movie);
      engine.hub.addError(
        const PlaybackError(
          kind: PlaybackErrorKind.network,
          message: 'tcp: Connection reset',
          recoverable: true,
        ),
      );
      await pumpEventQueue();
      expect(session.status, isA<PlaybackSessionReady>());
      expect(session.isRecoveringFromNetworkError, isTrue);

      engine.hub.addError(
        const PlaybackError(kind: PlaybackErrorKind.decoder, message: 'bad'),
      );
      await pumpEventQueue();
      expect(
        (session.status as PlaybackSessionFailed).message,
        contains('bad'),
      );
    },
  );

  test('compatibility preference starts with mpv on Android', () {
    final mpv = FakePlaybackEngine();
    final android = PlaybackSession(
      selector: const EngineSelector([
        CompatibilityModeRule(),
        AndroidMedia3Rule(),
        DefaultMpvTextureRule(),
      ]),
      factory: PlaybackEngineFactory({
        PlaybackEngineKind.media3:
            () => FakePlaybackEngine(kind: PlaybackEngineKind.media3),
        PlaybackEngineKind.mpvTexture: () => mpv,
      }),
      environment: const PlatformEnvironment(platform: TargetPlatform.android),
      resolver: resolver,
      sourceGateway: sourceGateway,
      progressGateway: progressGateway,
      defaultRate: () => 1.0,
      enginePreference: EnginePreference.compatibility,
    );
    addTearDown(android.dispose);
    expect(android.engine, same(mpv));
  });

  test('falls back to the next engine from the same position', () async {
    final media3 = FakePlaybackEngine(kind: PlaybackEngineKind.media3);
    final mpv = FakePlaybackEngine();
    final android = PlaybackSession(
      selector: const EngineSelector([
        AndroidMedia3Rule(),
        DefaultMpvTextureRule(),
      ]),
      factory: PlaybackEngineFactory({
        PlaybackEngineKind.media3: () => media3,
        PlaybackEngineKind.mpvTexture: () => mpv,
      }),
      environment: const PlatformEnvironment(platform: TargetPlatform.android),
      resolver: resolver,
      sourceGateway: sourceGateway,
      progressGateway: progressGateway,
      defaultRate: () => 1.0,
    );
    addTearDown(android.dispose);
    final androidNotices = <String>[];
    android.notices.listen(androidNotices.add);

    await android.load(movie);
    media3.hub.update(duration: hour, position: const Duration(minutes: 5));
    media3.hub.addError(
      const PlaybackError(
        kind: PlaybackErrorKind.decoder,
        message: '无法解码杜比视界 Profile 5',
        fallbackSuggested: true,
      ),
    );
    await pumpEventQueue();

    expect(android.engine, same(mpv));
    expect(media3.disposed, isTrue);
    expect(
      mpv.calls,
      containsAllInOrder(['initialize', 'open http://media.local/a.mkv']),
    );
    expect(androidNotices.last, contains('已切换到 mpv'));
    expect(android.status, isA<PlaybackSessionReady>());

    mpv.hub.update(duration: hour);
    await pumpEventQueue();
    expect(mpv.calls.last, 'seek 300');
  });

  test('fallback without another engine fails the session', () async {
    await session.load(movie);
    engine.hub.addError(
      const PlaybackError(
        kind: PlaybackErrorKind.decoder,
        message: 'no decoder',
        fallbackSuggested: true,
      ),
    );
    await pumpEventQueue();
    expect(
      (session.status as PlaybackSessionFailed).message,
      contains('no decoder'),
    );
  });

  test('auto loads best external subtitle and skips embedded pick', () async {
    sourceGateway.subtitles = [subtitleInfo('chs', 95, language: 'chs')];
    await session.load(movie);
    await pumpEventQueue();
    engine.hub.update(
      tracks: const MediaTracks(
        subtitle: [SubtitleTrackInfo(id: '2', language: 'chi')],
      ),
    );
    await pumpEventQueue();

    expect(session.externalSubtitles, hasLength(1));
    expect(engine.calls, contains('external chs (chs)'));
    expect(engine.calls.where((c) => c.startsWith('subtitle')), isEmpty);
    expect(notices, ['已自动加载字幕: chs (chs)']);
  });

  test('selects embedded chinese subtitle when no external one fits', () async {
    await session.load(movie);
    engine.hub.update(
      tracks: const MediaTracks(
        subtitle: [
          SubtitleTrackInfo(id: '1', language: 'eng'),
          SubtitleTrackInfo(id: '2', title: '简体', language: 'chi'),
        ],
      ),
    );
    await pumpEventQueue();

    expect(engine.calls, contains('subtitle 2'));
    expect(notices, ['已自动选择内嵌字幕: 简体']);
  });

  test('local cache shows a notice and skips external subtitles', () async {
    resolver.result = const ResolvedPlayback(
      PlaybackSource.localFile('/downloads/a.mkv'),
    );
    sourceGateway.subtitles = [subtitleInfo('chs', 95)];
    await session.load(movie);
    await pumpEventQueue();

    expect(notices, ['正在使用本地缓存播放']);
    expect(session.externalSubtitles, isEmpty);
  });

  test('restores the session volume after opening', () async {
    session.rememberVolume(1.5);
    await session.load(movie);
    expect(engine.calls, ['open http://media.local/a.mkv', 'volume 1.5']);
  });

  test('prepareExit pauses and saves progress', () async {
    await session.load(movie);
    engine.hub.update(duration: hour, position: const Duration(seconds: 300));
    await pumpEventQueue();
    await session.prepareExit();

    expect(engine.calls, contains('pause'));
    expect(progressGateway.uploads, ['300/3600']);
  });

  test('dispose saves synchronously and releases the engine', () async {
    await session.load(movie);
    engine.hub.update(duration: hour, position: const Duration(seconds: 61));
    await pumpEventQueue();
    session.dispose();
    await pumpEventQueue();

    expect(progressGateway.publishes, ['61/3600']);
    expect(engine.disposed, isTrue);
    expect(resolver.disposed, isTrue);
  });
}
