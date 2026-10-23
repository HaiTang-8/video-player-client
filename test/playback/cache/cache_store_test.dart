import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/playback/cache/byte_range.dart';
import 'package:media_player/playback/cache/cache_store.dart';

void main() {
  const blockSize = 1024;
  const size = 10 * blockSize + 300;
  final source = List<int>.generate(size, (i) => (i * 31 + 7) % 256);
  late Directory dir;
  late DateTime now;
  late CacheStore store;

  CacheStore newStore() => CacheStore(
    Directory('${dir.path}/cache'),
    blockSize: blockSize,
    resumeBefore: 1000,
    resumeAfter: 1000,
    metaSaveDelay: const Duration(milliseconds: 10),
    now: () => now,
  );

  Future<void> writeRange(String id, int start, int end) =>
      store.write(id, start, source.sublist(start, end));

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('cache_store_test');
    now = DateTime(2026, 10, 23);
    store = newStore();
    await store.open();
  });

  tearDown(() async {
    await store.close();
    await dir.delete(recursive: true);
  });

  test('writes and reads unaligned ranges across blocks', () async {
    await store.prepare('a', size: size);
    await writeRange('a', 1000, 5000);

    expect(store['a']!.cachedRanges, const [ByteRange(1000, 5000)]);
    expect(store.usedBytes, 4000);
    expect(
      await store.read('a', const ByteRange(1500, 4100)),
      source.sublist(1500, 4100),
    );
    expect(() => store.read('a', const ByteRange(900, 1100)), throwsStateError);
  });

  test('caches a partial tail and the short last block', () async {
    await store.prepare('a', size: size);
    await writeRange('a', size - 64, size);
    await writeRange('a', 0, 100);

    final meta = store['a']!;
    expect(meta.cachedRunFrom(size - 64), 64);
    expect(meta.missing(const ByteRange(0, size)), const [
      ByteRange(100, size - 64),
    ]);
    expect(
      await store.read('a', const ByteRange(size - 64, size)),
      source.sublist(size - 64),
    );
  });

  test(
    'streaming writer commits each block and the remainder on close',
    () async {
      await store.prepare('a', size: size);
      final writer = store.writer('a', 2000);
      expect(store.isInUse('a'), isTrue);
      for (var offset = 2000; offset < 4500; offset += 300) {
        await writer.add(source.sublist(offset, (offset + 300).clamp(0, 4500)));
      }
      expect(store['a']!.cachedRunFrom(2000), 4096 - 2000, reason: '写满的块先提交');
      await writer.close();
      expect(store.isInUse('a'), isFalse);
      expect(store['a']!.cachedRunFrom(2000), 2500);
    },
  );

  test('ignores bytes past the end of the file', () async {
    await store.prepare('a', size: size);
    await store.write('a', size - 10, List.filled(50, 1));
    expect(store['a']!.cachedRanges, const [ByteRange(size - 10, size)]);
  });

  test(
    'reopening restores entries and reconciles the blocks on disk',
    () async {
      await store.prepare('a', size: size, etag: '"v1"', filePath: '/m/a.mkv');
      await writeRange('a', 0, 3 * blockSize);
      store
        ..pin('a', const ByteRange(0, 100))
        ..reportPlayback('a', positionMs: 5000, durationMs: 60000);
      await store.close();

      await File('${dir.path}/cache/a/blocks/1').delete();
      await File('${dir.path}/cache/a/blocks/99').writeAsString('orphan');
      await Directory('${dir.path}/cache/broken').create();
      await File('${dir.path}/cache/broken/meta.json').writeAsString('{bad');

      store = newStore();
      await store.open();
      final meta = store['a']!;
      expect(meta.blocks.keys.toList()..sort(), [0, 2]);
      expect(meta.filePath, '/m/a.mkv');
      expect(meta.pinned, const [ByteRange(0, 100)]);
      expect(meta.resumePositionMs, 5000);
      expect(meta.durationMs, 60000);
      expect(await File('${dir.path}/cache/a/blocks/99').exists(), isFalse);
      expect(await Directory('${dir.path}/cache/broken').exists(), isFalse);
      expect(store.entries.map((e) => e.id), ['a']);
      expect(
        await store.read('a', const ByteRange(2048, 3072)),
        source.sublist(2048, 3072),
      );
    },
  );

  test('metadata is replaced atomically', () async {
    await store.prepare('a', size: size);
    await writeRange('a', 0, 2000);
    await store.flush();
    final files =
        await Directory(
          '${dir.path}/cache/a',
        ).list().map((e) => e.path).toList();
    expect(files.any((p) => p.endsWith('meta.json')), isTrue);
    expect(files.any((p) => p.endsWith('.tmp')), isFalse);
  });

  test('a changed size or etag invalidates the entry', () async {
    await store.prepare('a', size: size, etag: '"v1"');
    await writeRange('a', 0, 2000);

    await store.prepare('a', size: size, etag: '"v1"');
    expect(store.usedBytes, 2000);

    await store.prepare('a', size: size, etag: '"v2"');
    expect(store.usedBytes, 0);
    await writeRange('a', 0, 1000);

    await store.prepare('a', size: size + 1);
    expect(store.usedBytes, 0);
    expect(await File('${dir.path}/cache/a/blocks/0').exists(), isFalse);
  });

  test('last-modified is used when there is no etag', () async {
    await store.prepare('a', size: size, lastModified: 'Mon');
    await writeRange('a', 0, 1000);
    await store.prepare('a', size: size, lastModified: 'Mon');
    expect(store.usedBytes, 1000);
    await store.prepare('a', size: size, lastModified: 'Tue');
    expect(store.usedBytes, 0);
  });

  test('trimming keeps the resume set and frees the other blocks', () async {
    await store.prepare('a', size: size);
    await writeRange('a', 0, size);
    store
      ..pin('a', const ByteRange(0, 100))
      ..pin('a', const ByteRange(size - 64, size))
      ..reportPlayback('a', positionMs: 5000, durationMs: 10000);
    // 续播点 5 秒 ≈ 偏移 5270，前后各 1000 字节落在第 4–6 块；固定区间在第 0、10 块
    await store.trim('a');
    expect(store['a']!.blocks.keys.toList()..sort(), [0, 4, 5, 6, 10]);
    expect(await File('${dir.path}/cache/a/blocks/3').exists(), isFalse);
    expect(await File('${dir.path}/cache/a/blocks/5').exists(), isTrue);
    expect(store.usedBytes, 4 * blockSize + 300);
  });

  test('enforcing the quota evicts the least recently used entries', () async {
    for (final (index, id) in ['old', 'mid', 'new'].indexed) {
      now = DateTime(2026, 10, 23, 10 + index);
      await store.prepare(id, size: size);
      await writeRange(id, 0, 4 * blockSize);
    }
    store.acquire('old');

    final plan = await store.enforce(6 * blockSize);
    expect(plan.actions.map((a) => a.id), ['mid', 'new']);
    expect(store['old'], isNotNull, reason: '使用中的条目不淘汰');
    expect(store.usedBytes, lessThanOrEqualTo((6 * blockSize * 0.95).floor()));

    store.release('old');
    await store.enforce(0, force: true);
    expect(store.entries, isEmpty);
    expect(store.usedBytes, 0);
  });

  test(
    'concurrent writers of overlapping ranges keep the data intact',
    () async {
      await store.prepare('a', size: size);
      final first = store.writer('a', 0);
      final second = store.writer('a', 1500);
      for (var i = 0; i < 40; i++) {
        final a = i * 300;
        final b = 1500 + i * 300;
        await Future.wait([
          if (a < 6000) first.add(source.sublist(a, (a + 300).clamp(0, 6000))),
          if (b < size) second.add(source.sublist(b, (b + 300).clamp(0, size))),
        ]);
      }
      await Future.wait([first.close(), second.close()]);

      expect(store['a']!.cachedRanges, const [ByteRange(0, size)]);
      expect(await store.read('a', const ByteRange(0, size)), source);
    },
  );

  test('a writer discards data after its entry is removed', () async {
    await store.prepare('a', size: size);
    final writer = store.writer('a', 0);
    await writer.add(source.sublist(0, 1500));
    await store.remove('a');
    await writer.add(source.sublist(1500, 3000));
    await writer.close();

    expect(store['a'], isNull);
    expect(await Directory('${dir.path}/cache/a').exists(), isFalse);
  });

  test('finds the most recent entry of an item', () async {
    await store.prepare('old', size: size);
    store.describe(
      'old',
      serverId: 's',
      itemKey: 'movie:1',
      filePath: '/a.mkv',
    );
    now = now.add(const Duration(hours: 1));
    await store.prepare('new', size: size);
    store.describe(
      'new',
      serverId: 's',
      itemKey: 'movie:1',
      filePath: '/b.mkv',
    );
    await store.prepare('other', size: size);
    store.describe('other', serverId: 's', itemKey: 'movie:2');

    expect(store.findByItem('s', 'movie:1')!.id, 'new');
    expect(store.findByItem('s', 'movie:3'), isNull);
    expect(store.findByItem('t', 'movie:1'), isNull);

    await store.close();
    store = newStore();
    await store.open();
    expect(store.findByItem('s', 'movie:1')!.filePath, '/b.mkv');
  });

  test('clear removes every entry', () async {
    await store.prepare('a', size: size);
    await store.prepare('b', size: size);
    await writeRange('a', 0, 1000);
    await store.clear();
    expect(store.entries, isEmpty);
    expect(await Directory('${dir.path}/cache').list().isEmpty, isTrue);
  });
}
