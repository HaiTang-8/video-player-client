import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/playback/session/seek_coordinator.dart';

import '../fakes/fake_playback_engine.dart';

void main() {
  late FakePlaybackEngine engine;
  late List<Duration> started;
  late int settled;
  late SeekCoordinator coordinator;

  setUp(() {
    engine = FakePlaybackEngine();
    started = [];
    settled = 0;
    coordinator = SeekCoordinator(
      engine: engine,
      onSeekStarted: started.add,
      onSeekSettled: () async => settled++,
      pollInterval: const Duration(milliseconds: 1),
    );
  });

  test('seeks, waits for the position and settles once', () async {
    await coordinator.seek(const Duration(seconds: 30));
    expect(coordinator.isActive, isTrue);
    await coordinator.awaitActive();

    expect(engine.calls, ['seek 30']);
    expect(started, [const Duration(seconds: 30)]);
    expect(settled, 1);
    expect(coordinator.isActive, isFalse);
  });

  test('a newer seek supersedes the pending one', () async {
    final gate = Completer<void>();
    engine.seekGate = gate;
    unawaited(coordinator.seek(const Duration(seconds: 10)));
    engine.seekGate = null;
    await coordinator.seek(const Duration(seconds: 20));
    gate.complete();
    await coordinator.awaitActive();
    await pumpEventQueue();

    expect(engine.calls, ['seek 10', 'seek 20']);
    expect(settled, 1);
  });

  test('engine seek failure is swallowed', () async {
    final gate = Completer<void>();
    engine.seekGate = gate;
    final future = coordinator.seek(const Duration(seconds: 5));
    gate.completeError(StateError('seek failed'));
    await future;
    await coordinator.awaitActive();
    expect(settled, 0);
  });
}
