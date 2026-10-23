import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'byte_range.dart';
import 'cache_entry_meta.dart';
import 'cache_eviction.dart';

/// 播放缓存的磁盘存储（纯 Dart，运行在代理隔离区）
///
/// 目录结构：`<root>/<entryId>/meta.json` 与 `<root>/<entryId>/blocks/<序号>`。
/// 块写入并刷盘后才在元数据里记为已缓存；元数据先写临时文件再改名
class CacheStore {
  CacheStore(
    this.root, {
    this.blockSize = 4 << 20,
    this.resumeBefore = 16 << 20,
    this.resumeAfter = 64 << 20,
    this.metaSaveDelay = const Duration(seconds: 2),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final Directory root;
  final int blockSize;

  /// 瘦身时保留续播点前后的字节数
  final int resumeBefore;
  final int resumeAfter;
  final Duration metaSaveDelay;
  final DateTime Function() _now;
  final Map<String, CacheEntryMeta> _entries = {};
  final Map<String, int> _users = {};
  final Set<String> _dirty = {};
  final Map<String, Future<void>> _locks = {};
  Future<void> _flushing = Future<void>.value();
  Timer? _saveTimer;

  Iterable<CacheEntryMeta> get entries => _entries.values;

  CacheEntryMeta? operator [](String id) => _entries[id];

  int get usedBytes => _entries.values.fold(0, (sum, e) => sum + e.cachedBytes);

  bool isInUse(String id) => (_users[id] ?? 0) > 0;

  /// 读取已有条目并与磁盘核对：元数据损坏的条目删除，丢失的块从记录中去掉，多余的文件删除
  Future<void> open() async {
    await root.create(recursive: true);
    await for (final dir in root.list()) {
      if (dir is! Directory) continue;
      final id = dir.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
      final meta = await _readMeta(id);
      if (meta == null) {
        await dir.delete(recursive: true);
        continue;
      }
      _entries[id] = meta;
      if (await _reconcile(meta)) await _saveMeta(meta);
    }
  }

  /// 取得或创建条目；大小或校验信息（ETag，没有时用 Last-Modified）与记录不一致时作废重建
  Future<CacheEntryMeta> prepare(
    String id, {
    required int size,
    String? contentType,
    String? etag,
    String? lastModified,
    String? filePath,
    int? storageId,
  }) async {
    final existing = _entries[id];
    if (existing != null &&
        _matches(
          existing,
          size: size,
          etag: etag,
          lastModified: lastModified,
        )) {
      existing
        ..lastAccess = _now()
        ..contentType = contentType ?? existing.contentType
        ..etag = etag ?? existing.etag
        ..lastModified = lastModified ?? existing.lastModified
        ..filePath = filePath ?? existing.filePath
        ..storageId = storageId ?? existing.storageId;
      _markDirty(id);
      return existing;
    }
    if (existing != null) await remove(id);
    final now = _now();
    final meta = CacheEntryMeta(
      id: id,
      size: size,
      blockSize: blockSize,
      createdAt: now,
      lastAccess: now,
      contentType: contentType,
      etag: etag,
      lastModified: lastModified,
      filePath: filePath,
      storageId: storageId,
    );
    await _serial(id, () => _blocksDir(id).create(recursive: true));
    _entries[id] = meta;
    await _saveMeta(meta);
    return meta;
  }

  /// 代理连接开始使用条目时调用；使用中的条目不参与淘汰
  void acquire(String id) => _users[id] = (_users[id] ?? 0) + 1;

  void release(String id) {
    final count = (_users[id] ?? 0) - 1;
    if (count > 0) {
      _users[id] = count;
    } else {
      _users.remove(id);
    }
  }

  /// 从 [offset] 开始顺序写入的写入器；写入期间条目视为使用中
  CacheWriter writer(String id, int offset) {
    final meta = _entries[id];
    if (meta == null) throw StateError('unknown cache entry $id');
    acquire(id);
    return CacheWriter._(this, meta, offset);
  }

  /// 一次写入一段数据
  Future<void> write(String id, int offset, List<int> bytes) async {
    final writer = this.writer(id, offset);
    try {
      await writer.add(bytes);
    } finally {
      await writer.close();
    }
  }

  /// 读取已缓存的区间；区间内有缺失时抛出 [StateError]
  Stream<List<int>> openRead(String id, ByteRange range) async* {
    final meta = _entries[id];
    if (meta == null || meta.cachedRunFrom(range.start) < range.length) {
      throw StateError('range $range of $id is not cached');
    }
    var cursor = range.start;
    while (cursor < range.end) {
      final index = cursor ~/ meta.blockSize;
      final span = meta.blockSpan(index);
      final end = math.min(range.end, span.end);
      yield* _blockFile(
        id,
        index,
      ).openRead(cursor - span.start, end - span.start);
      cursor = end;
    }
  }

  Future<List<int>> read(String id, ByteRange range) async {
    final bytes = <int>[];
    await for (final chunk in openRead(id, range)) {
      bytes.addAll(chunk);
    }
    return bytes;
  }

  void touch(String id) => _update(id, (m) => m.lastAccess = _now());

  /// 记录打开阶段读取的区间（封装头、索引）
  void pin(String id, ByteRange range) => _update(id, (m) => m.pin(range));

  /// 记录打开或 seek 后第一次读取的偏移与当时的播放位置
  void addSample(String id, int positionMs, int offset) =>
      _update(id, (m) => m.addSample(positionMs, offset));

  void reportPlayback(String id, {required int positionMs, int? durationMs}) =>
      _update(id, (m) {
        m.resumePositionMs = positionMs;
        if (durationMs != null && durationMs > 0) m.durationMs = durationMs;
      });

  /// 只保留续播集，删除其余块文件；使用中的条目跳过
  Future<void> trim(String id) async {
    final meta = _entries[id];
    if (meta == null || isInUse(id)) return;
    final keep = meta.blocksToKeep(before: resumeBefore, after: resumeAfter);
    final drop = meta.blocks.keys.where((i) => !keep.contains(i)).toList();
    if (drop.isEmpty) return;
    drop.forEach(meta.blocks.remove);
    await _serial(id, () async {
      for (final index in drop) {
        await _deleteQuietly(_blockFile(id, index));
      }
    });
    await _saveMeta(meta);
  }

  Future<void> remove(String id) async {
    _entries.remove(id);
    _dirty.remove(id);
    await _serial(id, () async {
      final dir = _entryDir(id);
      if (await dir.exists()) await dir.delete(recursive: true);
    });
  }

  Future<void> clear() async {
    for (final id in _entries.keys.toList()) {
      await remove(id);
    }
  }

  /// 按两级淘汰把占用降到 [limitBytes] 以内；使用中的条目跳过
  Future<EvictionPlan> enforce(int limitBytes, {bool force = false}) async {
    final plan = planEviction(
      [
        for (final meta in _entries.values)
          EvictionCandidate(
            id: meta.id,
            lastAccess: meta.lastAccess,
            usedBytes: meta.cachedBytes,
            keepBytes: _keepBytes(meta),
            inUse: isInUse(meta.id),
          ),
      ],
      limitBytes: limitBytes,
      force: force,
    );
    for (final action in plan.actions) {
      switch (action) {
        case TrimEntry(:final id):
          await trim(id);
        case DeleteEntry(:final id):
          await remove(id);
      }
    }
    return plan;
  }

  /// 立即保存所有待保存的元数据；会先等前一次保存（包括定时触发的）完成
  Future<void> flush() {
    _saveTimer?.cancel();
    _saveTimer = null;
    return _flushing = _flushing
        .catchError((Object _) {})
        .then((_) => _saveDirty());
  }

  Future<void> close() => flush();

  Future<void> _saveDirty() async {
    final ids = _dirty.toList();
    _dirty.clear();
    for (final id in ids) {
      final meta = _entries[id];
      if (meta != null) await _saveMeta(meta);
    }
  }

  int _keepBytes(CacheEntryMeta meta) {
    final keep = meta.blocksToKeep(before: resumeBefore, after: resumeAfter);
    return meta.blocks.entries
        .where((e) => keep.contains(e.key))
        .fold(0, (sum, e) => sum + e.value.length);
  }

  bool _matches(
    CacheEntryMeta meta, {
    required int size,
    String? etag,
    String? lastModified,
  }) {
    if (meta.size != size) return false;
    if (etag != null && meta.etag != null) return etag == meta.etag;
    if (lastModified != null && meta.lastModified != null) {
      return lastModified == meta.lastModified;
    }
    return true;
  }

  void _update(String id, void Function(CacheEntryMeta meta) change) {
    final meta = _entries[id];
    if (meta == null) return;
    change(meta);
    _markDirty(id);
  }

  void _markDirty(String id) {
    _dirty.add(id);
    _saveTimer ??= Timer(metaSaveDelay, () {
      _saveTimer = null;
      unawaited(flush().catchError((Object _) {}));
    });
  }

  /// 块写入并刷盘后调用；条目在写入期间被删除或重建时忽略
  void _commit(CacheEntryMeta meta, ByteRange range) {
    if (!identical(_entries[meta.id], meta)) return;
    meta.markCached(range);
    _markDirty(meta.id);
  }

  Future<bool> _reconcile(CacheEntryMeta meta) async {
    final dir = _blocksDir(meta.id);
    final onDisk = <int>{};
    if (await dir.exists()) {
      await for (final file in dir.list()) {
        final index = int.tryParse(file.uri.pathSegments.last);
        if (file is File && index != null && meta.blocks.containsKey(index)) {
          onDisk.add(index);
        } else {
          await _deleteQuietly(file);
        }
      }
    } else {
      await dir.create(recursive: true);
    }
    final lost = meta.blocks.keys.where((i) => !onDisk.contains(i)).toList();
    lost.forEach(meta.blocks.remove);
    return lost.isNotEmpty;
  }

  Future<CacheEntryMeta?> _readMeta(String id) async {
    try {
      final text = await _metaFile(id).readAsString();
      final meta = CacheEntryMeta.fromJson(
        jsonDecode(text) as Map<String, Object?>,
      );
      return meta.id == id ? meta : null;
    } catch (_) {
      return null;
    }
  }

  /// 条目已被删除或重建时不再保存，避免旧元数据覆盖新条目
  Future<void> _saveMeta(CacheEntryMeta meta) => _serial(meta.id, () async {
    if (!identical(_entries[meta.id], meta)) return;
    final file = _metaFile(meta.id);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(meta.toJson()), flush: true);
    await temp.rename(file.path);
  });

  /// 同一条目的目录操作（保存元数据、删除、瘦身）按顺序执行
  Future<void> _serial(String id, Future<void> Function() operation) {
    final run = (_locks[id] ?? Future<void>.value()).then((_) => operation());
    final tail = run.catchError((Object _) {});
    _locks[id] = tail;
    tail.whenComplete(() {
      if (identical(_locks[id], tail)) _locks.remove(id);
    });
    return run;
  }

  Future<void> _deleteQuietly(FileSystemEntity entity) async {
    try {
      await entity.delete(recursive: true);
    } catch (_) {}
  }

  Directory _entryDir(String id) => Directory('${root.path}/$id');

  Directory _blocksDir(String id) => Directory('${root.path}/$id/blocks');

  File _metaFile(String id) => File('${root.path}/$id/meta.json');

  File _blockFile(String id, int index) =>
      File('${root.path}/$id/blocks/$index');
}

/// 顺序写入器：按块拆分写入，每写满一块（以及关闭时）刷盘并记为已缓存
class CacheWriter {
  CacheWriter._(this._store, this._meta, this._offset);

  final CacheStore _store;
  final CacheEntryMeta _meta;
  int _offset;
  int? _blockIndex;
  int _blockStart = 0;
  RandomAccessFile? _file;
  bool _closed = false;

  /// 下一个字节写入的位置
  int get offset => _offset;

  /// 条目在写入期间被删除或重建（例如用户清理缓存）时丢弃数据
  bool get _stale => !identical(_store._entries[_meta.id], _meta);

  Future<void> add(List<int> bytes) async {
    if (_closed) throw StateError('writer is closed');
    if (_stale) {
      _offset += bytes.length;
      return;
    }
    try {
      await _write(bytes);
    } on FileSystemException {
      if (!_stale) rethrow;
    }
  }

  Future<void> _write(List<int> bytes) async {
    var consumed = 0;
    while (consumed < bytes.length && _offset < _meta.size) {
      final index = _offset ~/ _meta.blockSize;
      if (index != _blockIndex) await _openBlock(index);
      final span = _meta.blockSpan(index);
      final take = math.min(bytes.length - consumed, span.end - _offset);
      await _file!.writeFrom(bytes, consumed, consumed + take);
      consumed += take;
      _offset += take;
      if (_offset == span.end) await _commitBlock();
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _commitBlock();
    } finally {
      _store.release(_meta.id);
    }
  }

  Future<void> _openBlock(int index) async {
    await _commitBlock();
    final span = _meta.blockSpan(index);
    final file = await _store
        ._blockFile(_meta.id, index)
        .open(mode: FileMode.append);
    await file.setPosition(_offset - span.start);
    _file = file;
    _blockIndex = index;
    _blockStart = _offset;
  }

  Future<void> _commitBlock() async {
    final file = _file;
    if (file == null) return;
    _file = null;
    _blockIndex = null;
    try {
      await file.flush();
    } finally {
      await file.close();
    }
    if (_offset > _blockStart) {
      _store._commit(_meta, ByteRange(_blockStart, _offset));
    }
  }
}
