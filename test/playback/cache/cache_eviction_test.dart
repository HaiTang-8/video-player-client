import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/playback/cache/cache_eviction.dart';

EvictionCandidate _entry(
  String id,
  int day,
  int used,
  int keep, {
  bool inUse = false,
}) => EvictionCandidate(
  id: id,
  lastAccess: DateTime(2026, 10, day),
  usedBytes: used,
  keepBytes: keep,
  inUse: inUse,
);

String _describe(EvictionAction a) =>
    '${a is TrimEntry ? 'trim' : 'delete'} ${a.id} ${a.freedBytes}';

void main() {
  test('does nothing below the high watermark', () {
    final plan = planEviction([
      _entry('a', 1, 600, 100),
      _entry('b', 2, 440, 100),
    ], limitBytes: 1000);
    expect(plan.actions, isEmpty);
    expect(plan.bytesAfter, 1040);
  });

  test('trims the least recently used entries first', () {
    final plan = planEviction([
      _entry('new', 3, 400, 100),
      _entry('old', 1, 400, 100),
      _entry('mid', 2, 400, 100),
    ], limitBytes: 1000);
    // 目标是降到上限的 95%：瘦身最旧的一条就够了
    expect(plan.actions.map(_describe), ['trim old 300']);
    expect(plan.bytesAfter, 900);
  });

  test('deletes after trimming everything is not enough', () {
    final plan = planEviction([
      _entry('a', 1, 500, 400),
      _entry('b', 2, 500, 400),
      _entry('c', 3, 500, 400),
    ], limitBytes: 600);
    // 被删除条目之前的瘦身动作会被替换掉
    expect(plan.actions.map(_describe), [
      'trim c 100',
      'delete a 500',
      'delete b 500',
    ]);
    expect(plan.bytesAfter, 400);
  });

  test('skips entries in use', () {
    final plan = planEviction([
      _entry('playing', 1, 900, 100, inUse: true),
      _entry('b', 2, 300, 100),
    ], limitBytes: 1100);
    expect(plan.actions.map(_describe), ['trim b 200']);
    expect(plan.bytesAfter, 1000);

    final tighter = planEviction([
      _entry('playing', 1, 900, 100, inUse: true),
      _entry('b', 2, 300, 100),
    ], limitBytes: 1000);
    expect(tighter.actions.map(_describe), ['delete b 300']);
    expect(tighter.bytesAfter, 900);
  });

  test('force starts as soon as the limit is exceeded', () {
    final entries = [_entry('a', 1, 1020, 100)];
    expect(planEviction(entries, limitBytes: 1000).actions, isEmpty);
    expect(
      planEviction(
        entries,
        limitBytes: 1000,
        force: true,
      ).actions.map(_describe),
      ['trim a 920'],
    );
  });

  test('entries without a resume set are deleted instead of trimmed', () {
    final plan = planEviction([
      _entry('bare', 1, 800, 0),
      _entry('b', 2, 400, 100),
    ], limitBytes: 1000);
    expect(plan.actions.map(_describe), ['delete bare 800']);
    expect(plan.bytesAfter, 400);
  });

  test('a zero limit removes everything not in use', () {
    final plan = planEviction([
      _entry('a', 1, 10, 5),
      _entry('b', 2, 10, 5, inUse: true),
    ], limitBytes: 0);
    expect(plan.actions.map(_describe), ['delete a 10']);
    expect(plan.bytesAfter, 10);
  });

  test('effective limit keeps a reserve of free space', () {
    const gib = 1 << 30;
    expect(
      effectiveCacheLimit(
        quotaBytes: 2 * gib,
        usedBytes: 0,
        freeBytes: 50 * gib,
      ),
      2 * gib,
    );
    expect(
      effectiveCacheLimit(
        quotaBytes: 10 * gib,
        usedBytes: gib,
        freeBytes: 2 * gib,
      ),
      2 * gib,
    );
    expect(
      effectiveCacheLimit(
        quotaBytes: 10 * gib,
        usedBytes: 0,
        freeBytes: gib ~/ 2,
      ),
      0,
    );
  });
}
