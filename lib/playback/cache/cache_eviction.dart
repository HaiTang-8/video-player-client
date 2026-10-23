import 'dart:math' as math;

/// 淘汰计算的输入：一个条目的占用情况
final class EvictionCandidate {
  const EvictionCandidate({
    required this.id,
    required this.lastAccess,
    required this.usedBytes,
    required this.keepBytes,
    this.inUse = false,
  });

  final String id;
  final DateTime lastAccess;
  final int usedBytes;

  /// 瘦身为续播集后剩下的字节数
  final int keepBytes;

  /// 正在被代理连接使用，不参与淘汰
  final bool inUse;
}

sealed class EvictionAction {
  const EvictionAction(this.id, this.freedBytes);

  final String id;
  final int freedBytes;
}

/// 只保留续播集
final class TrimEntry extends EvictionAction {
  const TrimEntry(super.id, super.freedBytes);
}

/// 整条删除
final class DeleteEntry extends EvictionAction {
  const DeleteEntry(super.id, super.freedBytes);
}

final class EvictionPlan {
  const EvictionPlan(this.actions, this.bytesAfter);

  final List<EvictionAction> actions;
  final int bytesAfter;
}

const evictionHighWatermark = 1.05;
const evictionLowWatermark = 0.95;

/// 两级淘汰（D1）：超过上限的 105% 时开始，按最后访问时间从旧到新先瘦身为续播集，
/// 仍超出再整条删除，直到降到上限的 95%。[force] 为 true 时只要超过上限就开始（调小配额时）
EvictionPlan planEviction(
  List<EvictionCandidate> entries, {
  required int limitBytes,
  bool force = false,
}) {
  var total = entries.fold<int>(0, (sum, e) => sum + e.usedBytes);
  final limit = math.max(0, limitBytes);
  final trigger = force ? limit : (limit * evictionHighWatermark).floor();
  if (total <= trigger) return EvictionPlan(const [], total);

  final target = (limit * evictionLowWatermark).floor();
  final candidates =
      entries.where((e) => !e.inUse).toList()
        ..sort((a, b) => a.lastAccess.compareTo(b.lastAccess));
  final actions = <EvictionAction>[];
  final remaining = {for (final e in candidates) e.id: e.usedBytes};
  final deleted = <String>{};

  for (final entry in candidates) {
    if (total <= target) break;
    final keep = math.min<int>(entry.keepBytes, entry.usedBytes);
    if (keep <= 0) {
      // 没有续播集可留，瘦身就等于删除，不留下只有元数据的空条目
      actions.add(DeleteEntry(entry.id, entry.usedBytes));
      deleted.add(entry.id);
      total -= entry.usedBytes;
      continue;
    }
    final freed = entry.usedBytes - keep;
    if (freed <= 0) continue;
    actions.add(TrimEntry(entry.id, freed));
    remaining[entry.id] = keep;
    total -= freed;
  }
  for (final entry in candidates) {
    if (total <= target) break;
    if (deleted.contains(entry.id)) continue;
    actions.removeWhere((a) => a is TrimEntry && a.id == entry.id);
    actions.add(DeleteEntry(entry.id, entry.usedBytes));
    total -= remaining[entry.id]!;
  }
  return EvictionPlan(actions, total);
}

/// 实际可用的缓存上限：min(配额, 已用 + 剩余空间 − 保留空间)，不足时为 0（只透传不写盘）
int effectiveCacheLimit({
  required int quotaBytes,
  required int usedBytes,
  required int freeBytes,
  int reserveBytes = 1 << 30,
}) => math.max(0, math.min(quotaBytes, usedBytes + freeBytes - reserveBytes));
