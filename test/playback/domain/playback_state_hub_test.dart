import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/playback/domain/playback_domain.dart';

void main() {
  test('updates snapshot and emits only changed values', () async {
    final hub = PlaybackStateHub();
    final positions = <Duration>[];
    final playing = <bool>[];
    hub.streams.position.listen(positions.add);
    hub.streams.playing.listen(playing.add);

    hub.update(position: const Duration(seconds: 1), playing: false);
    hub.update(position: const Duration(seconds: 1));
    hub.update(position: const Duration(seconds: 2), rate: 1.5);
    await pumpEventQueue();

    expect(positions, [const Duration(seconds: 1), const Duration(seconds: 2)]);
    expect(playing, isEmpty);
    expect(hub.state.position, const Duration(seconds: 2));
    expect(hub.state.rate, 1.5);
    expect(hub.state.volume, 1.0);
  });

  test('compares tracks by value', () async {
    final hub = PlaybackStateHub();
    final events = <MediaTracks>[];
    hub.streams.tracks.listen(events.add);

    MediaTracks build() => const MediaTracks(
      audio: [AudioTrackInfo(id: '1', language: 'chi')],
      subtitle: [SubtitleTrackInfo(id: '2', title: '简体')],
    );
    hub.update(tracks: build());
    hub.update(tracks: build());
    await pumpEventQueue();

    expect(events, hasLength(1));
  });

  test('reset lets the next media re-emit the same duration', () async {
    final hub = PlaybackStateHub();
    final durations = <Duration>[];
    hub.streams.duration.listen(durations.add);
    const selected = SelectedTracks(subtitleOff: true);

    hub.update(duration: const Duration(minutes: 90), selectedTracks: selected);
    hub.resetForNewMedia();
    hub.update(duration: const Duration(minutes: 90));
    await pumpEventQueue();

    expect(durations, [
      const Duration(minutes: 90),
      Duration.zero,
      const Duration(minutes: 90),
    ]);
    expect(hub.state.selectedTracks, selected);
  });

  test('first frame flag resets for the next media', () async {
    final hub = PlaybackStateHub();
    final frames = <bool>[];
    hub.streams.firstFrameRendered.listen(frames.add);

    hub
      ..update(firstFrameRendered: true)
      ..update(firstFrameRendered: true)
      ..resetForNewMedia();
    expect(hub.state.firstFrameRendered, isFalse);
    hub.update(firstFrameRendered: true);
    await pumpEventQueue();

    expect(frames, [true, false, true]);
  });

  test('stops emitting after close', () async {
    final hub = PlaybackStateHub();
    var done = false;
    hub.streams.errors.listen(
      (_) => fail('unexpected error'),
      onDone: () => done = true,
    );

    await hub.close();
    hub.update(position: const Duration(seconds: 5));
    hub.addError(
      const PlaybackError(kind: PlaybackErrorKind.unknown, message: 'x'),
    );
    await hub.close();

    expect(done, isTrue);
    expect(hub.state.position, Duration.zero);
  });
}
