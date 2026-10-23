import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/playback/cache/byte_range.dart';
import 'package:media_player/playback/cache/cache_entry_key.dart';
import 'package:media_player/playback/cache/cache_entry_meta.dart';

CacheEntryMeta _meta({int size = 10000, int blockSize = 1000}) =>
    CacheEntryMeta(
      id: 'e',
      size: size,
      blockSize: blockSize,
      createdAt: DateTime(2026),
      lastAccess: DateTime(2026),
    );

void main() {
  group('ByteRange.merge', () {
    test('merges overlapping and adjacent ranges and drops empty ones', () {
      expect(
        ByteRange.merge(const [
          ByteRange(50, 60),
          ByteRange(0, 10),
          ByteRange(10, 20),
          ByteRange(15, 30),
          ByteRange(40, 40),
        ]),
        const [ByteRange(0, 30), ByteRange(50, 60)],
      );
    });
  });

  group('block coverage', () {
    test('merges pieces across block boundaries', () {
      final meta =
          _meta()
            ..markCached(const ByteRange(500, 2500))
            ..markCached(const ByteRange(2500, 2600));
      expect(meta.blocks, {
        0: const ByteRange(500, 1000),
        1: const ByteRange(0, 1000),
        2: const ByteRange(0, 600),
      });
      expect(meta.cachedRanges, const [ByteRange(500, 2600)]);
      expect(meta.cachedBytes, 2100);
      expect(meta.cachedRunFrom(700), 1900);
      expect(meta.cachedRunFrom(400), 0);
      expect(meta.cachedRunFrom(2600), 0);
    });

    test('reports missing gaps inside a range', () {
      final meta =
          _meta()
            ..markCached(const ByteRange(1000, 2000))
            ..markCached(const ByteRange(3500, 3700));
      expect(meta.missing(const ByteRange(0, 4000)), const [
        ByteRange(0, 1000),
        ByteRange(2000, 3500),
        ByteRange(3700, 4000),
      ]);
      expect(meta.missing(const ByteRange(1200, 1800)), isEmpty);
      expect(meta.missing(const ByteRange(9500, 20000)), const [
        ByteRange(9500, 10000),
      ]);
    });

    test('keeps the longer piece when two pieces of a block are disjoint', () {
      final meta =
          _meta()
            ..markCached(const ByteRange(100, 200))
            ..markCached(const ByteRange(500, 900));
      expect(meta.blocks[0], const ByteRange(500, 900));
      meta.markCached(const ByteRange(0, 50));
      expect(meta.blocks[0], const ByteRange(500, 900));
    });

    test('handles a short last block', () {
      final meta = _meta(size: 2500)..markCached(const ByteRange(0, 9999));
      expect(meta.blockCount, 3);
      expect(meta.blocks[2], const ByteRange(0, 500));
      expect(meta.isComplete, isTrue);
      expect(meta.cachedRunFrom(0), 2500);
    });
  });

  group('resume set', () {
    test('pins merge and stay within the file', () {
      final meta =
          _meta()
            ..pin(const ByteRange(0, 300))
            ..pin(const ByteRange(200, 600))
            ..pin(const ByteRange(9900, 12000));
      expect(meta.pinned, const [ByteRange(0, 600), ByteRange(9900, 10000)]);
    });

    test('samples replace nearby positions and stay sorted and bounded', () {
      final meta = _meta(size: 1 << 30);
      meta
        ..addSample(60000, 600)
        ..addSample(10000, 100)
        ..addSample(61000, 610);
      expect(meta.samples.map((s) => s.positionMs), [10000, 61000]);
      for (var i = 0; i < 200; i++) {
        meta.addSample(100000 + i * 5000, 1000 + i);
      }
      expect(meta.samples.length, 64);
      final positions = meta.samples.map((s) => s.positionMs).toList();
      expect(positions, [...positions]..sort());
    });

    test('estimates offsets from samples, then from the average bitrate', () {
      final meta = _meta(size: 1000000)..durationMs = 100000;
      expect(meta.estimateOffset(50000), 500000);

      meta.addSample(10000, 200000);
      expect(meta.estimateOffset(20000), 300000);

      meta.addSample(30000, 400000);
      expect(meta.estimateOffset(20000), 300000);
      expect(meta.estimateOffset(40000), 500000);
      expect(meta.estimateOffset(0), 100000);
      expect(meta.estimateOffset(1000000), 999999);

      expect(_meta().estimateOffset(1000), isNull);
    });

    test('keeps pinned ranges and a window around the resume point', () {
      final meta =
          _meta(size: 100000)
            ..durationMs = 100000
            ..resumePositionMs = 50000
            ..pin(const ByteRange(0, 100))
            ..markCached(const ByteRange(0, 100000));
      expect(meta.resumeSet(before: 2000, after: 3000), const [
        ByteRange(0, 100),
        ByteRange(48000, 53000),
      ]);
      expect(meta.blocksToKeep(before: 2000, after: 3000).toList()..sort(), [
        0,
        48,
        49,
        50,
        51,
        52,
      ]);
    });
  });

  test('round-trips through JSON', () {
    final meta =
        _meta()
          ..etag = '"abc"'
          ..filePath = '/m/a.mkv'
          ..storageId = 3
          ..serverId = 'http://media.local:80'
          ..itemKey = 'movie:1'
          ..resumePositionMs = 1234
          ..durationMs = 99999
          ..markCached(const ByteRange(900, 2100))
          ..pin(const ByteRange(0, 64))
          ..addSample(1000, 900);
    final copy = CacheEntryMeta.fromJson(meta.toJson());
    expect(copy.toJson(), meta.toJson());
    expect(copy.cachedRanges, const [ByteRange(900, 2100)]);
  });

  group('CacheEntryKey', () {
    test('normalizes the server and ignores signed urls', () {
      final a = CacheEntryKey.forServer(
        'HTTP://Media.Local:8080/',
        itemKey: 'movie:1',
        filePath: '/m/a.mkv',
      );
      final b = CacheEntryKey.forServer(
        'http://media.local:8080/api',
        itemKey: 'movie:1',
        filePath: '/m/a.mkv',
      );
      expect(a.serverId, 'http://media.local:8080');
      expect(a, b);
      expect(a.id, b.id);
      expect(a.id, hasLength(40));
    });

    test('different sources of the same episode get different ids', () {
      const base = CacheEntryKey(serverId: 's', itemKey: 'episode:1/2/3');
      const other = CacheEntryKey(
        serverId: 's',
        itemKey: 'episode:1/2/3',
        filePath: '/b.mkv',
      );
      expect(base.id, isNot(other.id));
    });
  });
}
