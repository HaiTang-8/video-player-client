import 'dart:math' as math;

import 'byte_range.dart';

/// 播放位置与对应字节偏移的一次采样（打开或 seek 后第一次读取时记录）
final class ResumeSample {
  const ResumeSample(this.positionMs, this.offset);

  final int positionMs;
  final int offset;
}

/// 一个缓存条目的元数据，对应磁盘上的 `meta.json`
///
/// 数据按固定大小的块分别存成文件，每块只记录一段有效区间（相对块起点）。
/// 局部数据（例如只读了末尾 64KiB）也能缓存；瘦身时删除块文件即可释放空间
final class CacheEntryMeta {
  CacheEntryMeta({
    required this.id,
    required this.size,
    required this.blockSize,
    required this.createdAt,
    required this.lastAccess,
    this.contentType,
    this.etag,
    this.lastModified,
    this.filePath,
    this.storageId,
    this.serverId,
    this.itemKey,
    this.resumePositionMs,
    this.durationMs,
    Map<int, ByteRange>? blocks,
    List<ByteRange>? pinned,
    List<ResumeSample>? samples,
  }) : blocks = blocks ?? {},
       pinned = pinned ?? [],
       samples = samples ?? [];

  static const _maxPinned = 32;
  static const _maxSamples = 64;
  static const _sampleMergeMs = 2000;

  final String id;
  final int size;
  final int blockSize;
  final DateTime createdAt;
  DateTime lastAccess;
  String? contentType;
  String? etag;
  String? lastModified;
  String? filePath;
  int? storageId;

  /// 与 [itemKey] 一起用于命中查找：不先请求流地址 API 也能找到这部片子的缓存
  String? serverId;
  String? itemKey;
  int? resumePositionMs;
  int? durationMs;

  /// 块序号 → 块内有效区间
  final Map<int, ByteRange> blocks;

  /// 打开阶段读取的区间（封装头、索引），淘汰时始终保留
  List<ByteRange> pinned;

  /// 按 positionMs 升序
  final List<ResumeSample> samples;

  int get blockCount => size <= 0 ? 0 : (size + blockSize - 1) ~/ blockSize;

  ByteRange blockSpan(int index) =>
      ByteRange(index * blockSize, math.min(size, (index + 1) * blockSize));

  int get cachedBytes => blocks.values.fold(0, (sum, r) => sum + r.length);

  bool get isComplete =>
      blocks.length == blockCount &&
      blocks.entries.every((e) => e.value.length == blockSpan(e.key).length);

  /// 已缓存的绝对区间，相邻的块会连成一段
  List<ByteRange> get cachedRanges => ByteRange.merge([
    for (final e in blocks.entries)
      ByteRange(
        e.key * blockSize + e.value.start,
        e.key * blockSize + e.value.end,
      ),
  ]);

  /// 从 [offset] 起连续已缓存的字节数
  int cachedRunFrom(int offset) {
    for (final range in cachedRanges) {
      if (range.start > offset) break;
      if (offset < range.end) return range.end - offset;
    }
    return 0;
  }

  /// [range] 中尚未缓存的子区间
  List<ByteRange> missing(ByteRange range) {
    final clamped = range.intersect(ByteRange(0, size));
    if (clamped == null) return const [];
    final gaps = <ByteRange>[];
    var cursor = clamped.start;
    for (final cached in cachedRanges) {
      if (cached.end <= cursor) continue;
      if (cached.start >= clamped.end) break;
      if (cached.start > cursor) gaps.add(ByteRange(cursor, cached.start));
      cursor = math.max(cursor, cached.end);
      if (cursor >= clamped.end) break;
    }
    if (cursor < clamped.end) gaps.add(ByteRange(cursor, clamped.end));
    return gaps;
  }

  /// 记录一段绝对区间已写入并刷盘。与块内已有区间重叠或相邻时合并；
  /// 不相连时保留较长的一段（每块只记一段）
  void markCached(ByteRange range) {
    final clamped = range.intersect(ByteRange(0, size));
    if (clamped == null) return;
    for (
      var index = clamped.start ~/ blockSize;
      index * blockSize < clamped.end;
      index++
    ) {
      final span = blockSpan(index);
      final piece = clamped.intersect(span)!;
      final local = ByteRange(piece.start - span.start, piece.end - span.start);
      final existing = blocks[index];
      if (existing == null) {
        blocks[index] = local;
      } else if (existing.overlapsOrTouches(local)) {
        blocks[index] = ByteRange(
          math.min(existing.start, local.start),
          math.max(existing.end, local.end),
        );
      } else if (local.length > existing.length) {
        blocks[index] = local;
      }
    }
  }

  void pin(ByteRange range) {
    final clamped = range.intersect(ByteRange(0, size));
    if (clamped == null) return;
    final merged = ByteRange.merge([...pinned, clamped]);
    pinned =
        merged.length <= _maxPinned
            ? merged
            : merged.sublist(merged.length - _maxPinned);
  }

  void addSample(int positionMs, int offset) {
    if (offset < 0 || offset >= size || positionMs < 0) return;
    samples.removeWhere(
      (s) => (s.positionMs - positionMs).abs() < _sampleMergeMs,
    );
    final at = samples.indexWhere((s) => s.positionMs > positionMs);
    samples.insert(
      at < 0 ? samples.length : at,
      ResumeSample(positionMs, offset),
    );
    while (samples.length > _maxSamples) {
      var closest = 1;
      for (var i = 2; i < samples.length; i++) {
        final gap = samples[i].positionMs - samples[i - 1].positionMs;
        final best =
            samples[closest].positionMs - samples[closest - 1].positionMs;
        if (gap < best) closest = i;
      }
      samples.removeAt(closest);
    }
  }

  /// 估算播放位置对应的字节偏移：优先用采样点插值，否则按平均码率
  int? estimateOffset(int positionMs) {
    final duration = durationMs;
    final bytesPerMs =
        duration != null && duration > 0 ? size / duration : null;
    int? estimate;
    if (samples.length >= 2) {
      var lower = samples.first;
      var upper = samples.last;
      for (final s in samples) {
        if (s.positionMs <= positionMs) lower = s;
        if (s.positionMs >= positionMs) {
          upper = s;
          break;
        }
      }
      if (positionMs < samples.first.positionMs) {
        lower = samples[0];
        upper = samples[1];
      } else if (positionMs > samples.last.positionMs) {
        lower = samples[samples.length - 2];
        upper = samples.last;
      }
      final span = upper.positionMs - lower.positionMs;
      final slope =
          span > 0 ? (upper.offset - lower.offset) / span : bytesPerMs ?? 0;
      estimate =
          (lower.offset + (positionMs - lower.positionMs) * slope).round();
    } else if (samples.length == 1) {
      final s = samples.single;
      estimate =
          (s.offset + (positionMs - s.positionMs) * (bytesPerMs ?? 0)).round();
    } else if (bytesPerMs != null) {
      estimate = (positionMs * bytesPerMs).round();
    }
    return estimate?.clamp(0, math.max(0, size - 1));
  }

  /// 续播集：固定区间 + 续播点前 [before] 到后 [after] 字节
  List<ByteRange> resumeSet({int before = 16 << 20, int after = 64 << 20}) {
    final position = resumePositionMs;
    final offset = position == null ? null : estimateOffset(position);
    return ByteRange.merge([
      ...pinned,
      if (offset != null)
        ByteRange(math.max(0, offset - before), math.min(size, offset + after)),
    ]);
  }

  /// 瘦身后要保留的块：与续播集相交的块整块保留
  Set<int> blocksToKeep({int before = 16 << 20, int after = 64 << 20}) {
    final keep = resumeSet(before: before, after: after);
    return {
      for (final index in blocks.keys)
        if (keep.any((r) => r.intersect(blockSpan(index)) != null)) index,
    };
  }

  Map<String, Object?> toJson() => {
    'version': 1,
    'id': id,
    'size': size,
    'blockSize': blockSize,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'lastAccess': lastAccess.millisecondsSinceEpoch,
    'contentType': contentType,
    'etag': etag,
    'lastModified': lastModified,
    'filePath': filePath,
    'storageId': storageId,
    'serverId': serverId,
    'itemKey': itemKey,
    'resumePositionMs': resumePositionMs,
    'durationMs': durationMs,
    'blocks': [
      for (final e in blocks.entries) [e.key, e.value.start, e.value.end],
    ],
    'pinned': [for (final r in pinned) r.toJson()],
    'samples': [
      for (final s in samples) [s.positionMs, s.offset],
    ],
  };

  static CacheEntryMeta fromJson(Map<String, Object?> json) => CacheEntryMeta(
    id: json['id'] as String,
    size: json['size'] as int,
    blockSize: json['blockSize'] as int,
    createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int),
    lastAccess: DateTime.fromMillisecondsSinceEpoch(json['lastAccess'] as int),
    contentType: json['contentType'] as String?,
    etag: json['etag'] as String?,
    lastModified: json['lastModified'] as String?,
    filePath: json['filePath'] as String?,
    storageId: json['storageId'] as int?,
    serverId: json['serverId'] as String?,
    itemKey: json['itemKey'] as String?,
    resumePositionMs: json['resumePositionMs'] as int?,
    durationMs: json['durationMs'] as int?,
    blocks: {
      for (final b in json['blocks'] as List)
        (b as List)[0] as int: ByteRange(b[1] as int, b[2] as int),
    },
    pinned: [for (final r in json['pinned'] as List) ByteRange.fromJson(r)],
    samples: [
      for (final s in json['samples'] as List)
        ResumeSample((s as List)[0] as int, s[1] as int),
    ],
  );
}
