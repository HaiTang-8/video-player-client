import 'dart:math' as math;

/// 半开字节区间 [start, end)
final class ByteRange {
  const ByteRange(this.start, this.end) : assert(start <= end);

  final int start;
  final int end;

  int get length => end - start;
  bool get isEmpty => end <= start;

  bool overlapsOrTouches(ByteRange other) =>
      start <= other.end && other.start <= end;

  ByteRange? intersect(ByteRange other) {
    final s = math.max(start, other.start);
    final e = math.min(end, other.end);
    return s < e ? ByteRange(s, e) : null;
  }

  List<int> toJson() => [start, end];

  static ByteRange fromJson(Object? json) {
    final list = json as List;
    return ByteRange(list[0] as int, list[1] as int);
  }

  /// 排序并合并重叠或相邻的区间
  static List<ByteRange> merge(Iterable<ByteRange> ranges) {
    final sorted =
        ranges.where((r) => !r.isEmpty).toList()
          ..sort((a, b) => a.start.compareTo(b.start));
    final merged = <ByteRange>[];
    for (final range in sorted) {
      final last = merged.isEmpty ? null : merged.last;
      if (last != null && last.overlapsOrTouches(range)) {
        merged[merged.length - 1] = ByteRange(
          last.start,
          math.max(last.end, range.end),
        );
      } else {
        merged.add(range);
      }
    }
    return merged;
  }

  @override
  bool operator ==(Object other) =>
      other is ByteRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => '[$start, $end)';
}
