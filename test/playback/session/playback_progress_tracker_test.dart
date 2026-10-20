import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/playback/session/playback_item.dart';
import 'package:media_player/playback/session/playback_progress_tracker.dart';

import '../fakes/fake_gateways.dart';
import '../fakes/fake_playback_engine.dart';

void main() {
  late FakePlaybackEngine engine;
  late FakeProgressGateway gateway;
  late DateTime now;
  late bool seeking;
  late PlaybackProgressTracker tracker;

  setUp(() {
    engine = FakePlaybackEngine();
    gateway = FakeProgressGateway();
    now = DateTime(2026, 10, 21, 20);
    seeking = false;
    tracker = PlaybackProgressTracker(
      engine: engine,
      gateway: gateway,
      isSeeking: () => seeking,
      clock: () => now,
    );
    engine.hub.update(duration: const Duration(hours: 1));
  });

  tearDown(() => tracker.stop());

  void at(int seconds) {
    final position = Duration(seconds: seconds);
    engine.hub.update(position: position);
    tracker.onPosition(position);
  }

  test(
    'saves only after start, with valid duration and moved position',
    () async {
      at(100);
      await tracker.save();
      expect(gateway.uploads, isEmpty);

      tracker.start(const MoviePlaybackItem(1));
      await tracker.save();
      await tracker.save();
      expect(gateway.uploads, ['100/3600']);
      expect(gateway.publishes, ['100/3600']);

      await tracker.save(force: true);
      expect(gateway.uploads, hasLength(2));
    },
  );

  test('skips periodic save while seeking unless forced', () async {
    tracker.start(const MoviePlaybackItem(1));
    at(100);
    seeking = true;
    await tracker.save();
    expect(gateway.uploads, isEmpty);
    await tracker.save(force: true);
    expect(gateway.uploads, ['100/3600']);
  });

  test(
    'position jumping near the end after a network error is ignored',
    () async {
      tracker.start(const MoviePlaybackItem(1));
      at(600);
      tracker.markNetworkError();
      at(3580);

      expect(tracker.hasRecentNetworkError, isTrue);
      expect(tracker.isSuspiciousCompletion(), isTrue);
      await tracker.save();
      await tracker.save(fromCompleted: true);
      expect(gateway.uploads, isEmpty);

      now = now.add(const Duration(seconds: 46));
      expect(tracker.hasRecentNetworkError, isFalse);
      at(3580);
      await tracker.save();
      expect(gateway.uploads, ['3580/3600']);
    },
  );

  test('controlled seek near the end is trusted', () async {
    tracker.start(const MoviePlaybackItem(1));
    at(600);
    tracker.markNetworkError();
    tracker.markControlledSeek(const Duration(seconds: 3570));
    at(3570);

    expect(tracker.isSuspiciousCompletion(), isFalse);
    await tracker.save(force: true);
    expect(gateway.uploads, ['3570/3600']);
  });

  test('saveSync publishes immediately and uploads without waiting', () {
    tracker.start(
      const EpisodePlaybackItem(tvShowId: 1, seasonId: 2, episodeId: 3),
    );
    at(42);
    tracker.saveSync();
    expect(gateway.publishes, ['42/3600']);
    expect(gateway.uploads, ['42/3600']);
  });

  test('does nothing when progress gateway is unavailable', () async {
    gateway.isAvailable = false;
    tracker.start(const MoviePlaybackItem(1));
    at(100);
    await tracker.save();
    tracker.saveSync();
    expect(gateway.uploads, isEmpty);
    expect(gateway.publishes, isEmpty);
  });
}
