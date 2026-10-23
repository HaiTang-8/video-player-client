import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/data/models/stream_info.dart';
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

class _RecordingObserver implements PlaybackSourceObserver {
  final List<String> events = [];

  @override
  void onOpening(Duration? startAt) =>
      events.add('opening ${startAt?.inSeconds}');

  @override
  void onFirstFrame() => events.add('firstFrame');

  @override
  void onSeek(Duration position) => events.add('seek ${position.inSeconds}');

  @override
  void onProgress(Duration position, Duration duration) =>
      events.add('progress ${position.inSeconds}/${duration.inSeconds}');
}

class _FakeResolver implements PlaybackSourceResolver {
  ResolvedPlayback? result;
  Object? error;

  /// 设置后 resolve 会等待它完成，用于模拟慢速解析
  Completer<void>? gate;
  int resolveCount = 0;
  bool disposed = false;

  @override
  Future<ResolvedPlayback> resolve(PlaybackItem item) async {
    resolveCount++;
    await gate?.future;
    final failure = error;
    if (failure != null) throw failure;
    return result!;
  }

  String? subtitleText;

  @override
  Future<String?> fetchSubtitleText(SubtitleInfo subtitle) async =>
      subtitleText ?? 'subtitle of ${subtitle.name}';

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

  test(
    'opens at the start position and applies rate once duration is known',
    () async {
      await session.load(movie, startAt: const Duration(seconds: 120));
      engine.hub.update(duration: hour);
      await pumpEventQueue();

      expect(engine.calls, ['open http://media.local/a.mkv @120', 'rate 1.25']);
      expect(engine.openedStartPosition, const Duration(seconds: 120));
    },
  );

  test(
    'start position guards progress against a bogus jump to the end',
    () async {
      await session.load(movie, startAt: const Duration(minutes: 50));
      engine.hub
        ..update(duration: hour)
        ..addError(
          const PlaybackError(
            kind: PlaybackErrorKind.network,
            message: 'reset',
            recoverable: true,
          ),
        );
      await pumpEventQueue();
      engine.hub.update(position: const Duration(minutes: 59));
      await pumpEventQueue();
      await session.prepareExit();

      expect(progressGateway.uploads, isEmpty);
    },
  );

  test('non-positive start position opens from the beginning', () async {
    await session.load(movie, startAt: Duration.zero);
    expect(engine.calls, ['open http://media.local/a.mkv']);
  });

  test('reports startup once playing at the start position', () async {
    await session.load(movie, startAt: const Duration(seconds: 120));
    engine.hub.update(playing: true, position: const Duration(seconds: 1));
    await pumpEventQueue();
    expect(session.lastStartup, isNull);

    engine.hub.update(position: const Duration(seconds: 120), buffering: true);
    await pumpEventQueue();
    expect(session.lastStartup, isNull);

    engine.hub.update(buffering: false);
    await pumpEventQueue();
    expect(session.lastStartup, isNull, reason: '位置还没有前进');

    engine.hub.update(position: const Duration(milliseconds: 120400));
    await pumpEventQueue();
    final report = session.lastStartup!;
    expect(report.target, const Duration(seconds: 120));
    expect(report.localFile, isFalse);
    expect(report.resolved, isNotNull);
    expect(report.opened, isNotNull);
    expect(report.firstPlaying, lessThanOrEqualTo(report.ready));
    expect(report.toString(), contains('target=120s'));
  });

  test('startup records when the first frame was shown', () async {
    await session.load(movie);
    engine.hub.update(firstFrameRendered: true, playing: true);
    await pumpEventQueue();
    engine.hub.update(position: const Duration(seconds: 1));
    await pumpEventQueue();

    final report = session.lastStartup!;
    expect(report.firstFrame, isNotNull);
    expect(report.firstFrame, lessThanOrEqualTo(report.ready));
    expect(report.toString(), contains('firstFrame='));
  });

  test('first frame of the previous media is not counted', () async {
    await session.load(movie);
    engine.hub.update(firstFrameRendered: true);
    await pumpEventQueue();

    resolver.gate = Completer<void>();
    final switching = session.load(movie);
    await pumpEventQueue();
    engine.hub.update(position: const Duration(seconds: 2));
    await pumpEventQueue();
    resolver.gate!.complete();
    await switching;
    engine.hub.update(playing: true);
    await pumpEventQueue();
    engine.hub.update(position: const Duration(seconds: 1));
    await pumpEventQueue();

    expect(session.lastStartup!.firstFrame, isNull);
  });

  test(
    'startup without a start position waits for playback progress',
    () async {
      await session.load(movie);
      engine.hub.update(playing: true);
      await pumpEventQueue();
      expect(session.lastStartup, isNull);

      engine.hub.update(position: const Duration(milliseconds: 500));
      await pumpEventQueue();
      expect(session.lastStartup!.target, isNull);
    },
  );

  test('failed load does not report startup', () async {
    engine.openError = Exception('boom');
    await session.load(movie);
    engine.hub.update(playing: true, position: const Duration(seconds: 5));
    await pumpEventQueue();
    expect(session.lastStartup, isNull);
  });

  group('start once the video view is attached', () {
    late PlaybackSession framed;

    setUp(() {
      engine.capabilities = const EngineCapabilities(
        dolbyVisionColor: false,
        maxVolume: 2.0,
        maxRate: 100,
        reportsVideoView: true,
      );
      framed = PlaybackSession(
        selector: const EngineSelector([DefaultMpvTextureRule()]),
        factory: PlaybackEngineFactory({
          PlaybackEngineKind.mpvTexture: () => engine,
        }),
        environment: const PlatformEnvironment(platform: TargetPlatform.macOS),
        resolver: resolver,
        sourceGateway: sourceGateway,
        progressGateway: progressGateway,
        defaultRate: () => 1.0,
        videoViewTimeout: const Duration(milliseconds: 100),
      );
      addTearDown(framed.dispose);
    });

    int plays() => engine.calls.where((c) => c == 'play').length;

    test('opens paused and plays once the view is attached', () async {
      await framed.load(movie, startAt: const Duration(minutes: 3));
      expect(engine.openedAutoPlay, isFalse);
      expect(framed.status, isA<PlaybackSessionReady>());
      expect(plays(), 0);

      engine.hub.update(videoViewAttached: true);
      await pumpEventQueue();
      expect(plays(), 1);

      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(plays(), 1);

      engine.hub.update(playing: true);
      await pumpEventQueue();
      engine.hub.update(position: const Duration(minutes: 3, seconds: 1));
      await pumpEventQueue();
      engine.hub.update(position: const Duration(minutes: 3, seconds: 2));
      await pumpEventQueue();
      final report = framed.lastStartup!;
      expect(report.viewAttached!, lessThanOrEqualTo(report.firstPlaying!));
      expect(report.toString(), contains('view='));
    });

    test('plays at once when the view is already attached', () async {
      engine.hub.update(videoViewAttached: true);
      await pumpEventQueue();
      await framed.load(movie);
      expect(plays(), 1);
    });

    test('plays after the timeout when the view never attaches', () async {
      await framed.load(movie);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(plays(), 0);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(plays(), 1);
    });

    test('a user who played and paused while waiting is left paused', () async {
      await framed.load(movie);
      engine.hub.update(playing: true);
      await pumpEventQueue();
      engine.hub.update(playing: false);
      await pumpEventQueue();
      engine.hub.update(videoViewAttached: true);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(plays(), 0);
    });

    test('leaving before the view attaches does not start playback', () async {
      await framed.load(movie);
      await framed.prepareExit();
      engine.hub.update(videoViewAttached: true);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(plays(), 0);
    });

    test('engines rendering without a native view still autoplay', () async {
      engine.capabilities = const EngineCapabilities(
        dolbyVisionColor: false,
        maxVolume: 2.0,
        maxRate: 100,
      );
      await framed.load(movie);
      expect(engine.openedAutoPlay, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(plays(), 0);
    });
  });

  group('source observer', () {
    late _RecordingObserver observer;

    setUp(() {
      observer = _RecordingObserver();
      resolver.result = ResolvedPlayback(
        const PlaybackSource.network('http://127.0.0.1:1/t/e/r1'),
        observer: observer,
      );
    });

    test(
      'hears opening before the engine opens and the first frame once',
      () async {
        resolver.gate = Completer<void>();
        final loading = session.load(
          movie,
          startAt: const Duration(seconds: 90),
        );
        await pumpEventQueue();
        expect(observer.events, isEmpty);
        resolver.gate!.complete();
        await loading;
        expect(observer.events, ['opening 90']);
        expect(engine.calls.first, 'open http://127.0.0.1:1/t/e/r1 @90');

        engine.hub.update(firstFrameRendered: true);
        await pumpEventQueue();
        engine.hub
          ..update(firstFrameRendered: false)
          ..update(firstFrameRendered: true);
        await pumpEventQueue();
        expect(observer.events, ['opening 90', 'firstFrame']);
      },
    );

    test('hears user seeks and throttled progress', () async {
      await session.load(movie);
      engine.hub.update(duration: hour, position: const Duration(seconds: 10));
      await pumpEventQueue();
      engine.hub.update(position: const Duration(seconds: 11));
      await pumpEventQueue();
      await session.seek(const Duration(minutes: 5));
      await session.prepareExit();

      expect(observer.events, [
        'opening null',
        'progress 10/3600',
        'seek 300',
        'progress 300/3600',
      ]);
    });
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

  test('subtitle style is applied on initialize and when changed', () async {
    await session.initialize();
    expect(engine.subtitleStyle, SubtitleStyle.defaults);

    const style = SubtitleStyle(scale: 1.2, color: 0xFFFBE5A0);
    session.setSubtitleStyle(style);
    await pumpEventQueue();
    expect(engine.subtitleStyle, style);
  });

  test(
    'subtitle delay goes to the engine and resets for another video',
    () async {
      engine.capabilities = const EngineCapabilities(
        dolbyVisionColor: false,
        maxVolume: 2.0,
        maxRate: 100,
        subtitleDelay: true,
      );
      await session.load(movie);
      session.setSubtitleDelay(const Duration(milliseconds: 500));
      await pumpEventQueue();
      expect(engine.subtitleDelay, const Duration(milliseconds: 500));

      await session.reload();
      expect(session.subtitleDelay.value, const Duration(milliseconds: 500));
      expect(engine.subtitleDelay, const Duration(milliseconds: 500));

      await session.load(const MoviePlaybackItem(2));
      expect(session.subtitleDelay.value, Duration.zero);
      expect(engine.subtitleDelay, Duration.zero);
    },
  );

  group('with a subtitle delay store', () {
    late FakeSubtitleDelayStore store;
    late PlaybackSession stored;

    EpisodePlaybackItem episode(int show, int id) =>
        EpisodePlaybackItem(tvShowId: show, seasonId: 1, episodeId: id);

    setUp(() {
      engine.capabilities = const EngineCapabilities(
        dolbyVisionColor: false,
        maxVolume: 2.0,
        maxRate: 100,
        subtitleDelay: true,
      );
      store = FakeSubtitleDelayStore();
      stored = PlaybackSession(
        selector: const EngineSelector([DefaultMpvTextureRule()]),
        factory: PlaybackEngineFactory({
          PlaybackEngineKind.mpvTexture: () => engine,
        }),
        environment: const PlatformEnvironment(platform: TargetPlatform.macOS),
        resolver: resolver,
        sourceGateway: sourceGateway,
        progressGateway: progressGateway,
        defaultRate: () => 1.0,
        subtitleDelayStore: store,
      );
    });

    tearDown(() => stored.dispose());

    test('delay is shared by episodes of the same show', () async {
      await stored.load(episode(1, 10));
      expect(stored.subtitleDelaySharedByShow, isTrue);
      stored.setSubtitleDelay(const Duration(milliseconds: 800));

      await stored.load(episode(1, 11));
      expect(store.saved['tv_1'], const Duration(milliseconds: 800));
      expect(stored.subtitleDelay.value, const Duration(milliseconds: 800));
      expect(engine.subtitleDelay, const Duration(milliseconds: 800));

      await stored.load(episode(2, 20));
      expect(stored.subtitleDelay.value, Duration.zero);
      expect(engine.subtitleDelay, Duration.zero);
    });

    test('movies keep their own delay', () async {
      store.saved['movie_1'] = const Duration(seconds: -1);
      await stored.load(movie);
      expect(stored.subtitleDelaySharedByShow, isFalse);
      expect(stored.subtitleDelay.value, const Duration(seconds: -1));
      expect(engine.subtitleDelay, const Duration(seconds: -1));
    });

    test('saves after adjustments settle and removes a zero delay', () async {
      await stored.load(episode(1, 10));
      stored
        ..setSubtitleDelay(const Duration(milliseconds: 100))
        ..setSubtitleDelay(const Duration(milliseconds: 200));
      expect(store.saved, isEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(store.saved['tv_1'], const Duration(milliseconds: 200));

      stored.setSubtitleDelay(Duration.zero);
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(store.saved, isEmpty);
    });

    test('pending delay is saved on dispose', () async {
      await stored.load(episode(1, 10));
      stored.setSubtitleDelay(const Duration(milliseconds: 300));
      stored.dispose();
      await pumpEventQueue();
      expect(store.saved['tv_1'], const Duration(milliseconds: 300));
    });
  });

  test(
    'without engine support the selected external subtitle is shifted',
    () async {
      resolver.subtitleText = '1\n00:00:01,000 --> 00:00:02,500\nhello\n';
      final sub = subtitleInfo('movie.chs.srt', 90);
      await session.load(movie);
      expect(session.subtitleDelaySupported, isFalse);

      await session.selectExternalSubtitle(sub);
      engine.hub.update(
        selectedTracks: SelectedTracks(
          subtitle: SubtitleTrackInfo(id: '2:0', title: sub.displayName),
        ),
      );
      expect(session.subtitleDelaySupported, isTrue);

      session.setSubtitleDelay(const Duration(milliseconds: 1500));
      await Future<void>.delayed(const Duration(milliseconds: 700));
      expect(
        engine.lastExternalText,
        '1\n00:00:02,500 --> 00:00:04,000\nhello\n',
      );
    },
  );

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
    expect(session.status, isA<PlaybackSessionReady>());
    expect(engine.calls.last, 'open http://media.local/a.mkv @90');
  });

  test('reopening the same media re-applies settings', () async {
    await session.load(movie);
    engine.hub.update(duration: hour);
    await pumpEventQueue();
    await session.load(movie, startAt: const Duration(seconds: 30));
    engine.hub.update(duration: hour);
    await pumpEventQueue();

    expect(engine.calls.where((c) => c.startsWith('rate')), hasLength(2));
    expect(engine.calls, contains('open http://media.local/a.mkv @30'));
    expect(engine.calls.where((c) => c.startsWith('seek')), isEmpty);
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
    expect(android.engineReason, '用户选择了兼容模式');
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
    expect(android.engineReason, 'Android 优先使用 Media3');
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
      containsAllInOrder(['initialize', 'open http://media.local/a.mkv @300']),
    );
    expect(androidNotices.last, contains('已切换到 mpv'));
    expect(android.engineReason, 'Media3 无法播放：无法解码杜比视界 Profile 5');
    expect(android.status, isA<PlaybackSessionReady>());
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

  test('local cache shows a notice and has nothing to load offline', () async {
    resolver.result = const ResolvedPlayback(
      PlaybackSource.localFile('/downloads/a.mkv'),
    );
    sourceGateway.subtitles = [subtitleInfo('chs', 95)];
    await session.load(movie);
    await pumpEventQueue();

    expect(notices, ['正在使用本地缓存播放']);
    expect(session.externalSubtitles, isEmpty);
  });

  group('local playback subtitles', () {
    setUp(() {
      resolver.result = const ResolvedPlayback(
        PlaybackSource.localFile('/downloads/a.mkv'),
      );
    });

    test('uses subtitles cached with the download', () async {
      final cached = subtitleInfo(
        'chs.srt',
        95,
      ).withLocalPath('/downloads/a.1.chs.srt');
      sourceGateway
        ..cached = [cached]
        ..subtitles = [subtitleInfo('server', 99)];
      await session.load(movie);
      await pumpEventQueue();

      expect(session.externalSubtitles, [cached]);
      expect(sourceGateway.streamRequests, isEmpty);
      expect(engine.calls, contains('external ${cached.displayName}'));
    });

    test('falls back to the server list when nothing is cached', () async {
      sourceGateway
        ..streamInfo = StreamInfo(
          url: '/stream',
          storageId: 1,
          filePath: '/movies/a.mkv',
        )
        ..subtitles = [subtitleInfo('chs', 95)];
      await session.load(movie);
      await pumpEventQueue();

      expect(session.externalSubtitles.map((s) => s.name), ['chs']);
    });

    test('offline without cache plays without external subtitles', () async {
      sourceGateway.streamInfoError = Exception('offline');
      await session.load(movie);
      await pumpEventQueue();

      expect(session.status, isA<PlaybackSessionReady>());
      expect(session.externalSubtitles, isEmpty);
    });
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
