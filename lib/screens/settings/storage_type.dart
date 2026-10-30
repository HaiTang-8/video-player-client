import 'package:flutter/cupertino.dart';

import '../../data/models/models.dart';

/// 存储源类型枚举
enum StorageType {
  webdav('webdav', 'WebDAV', CupertinoIcons.cloud, Color(0xFF007AFF)),
  local('local', '本地存储', CupertinoIcons.folder, Color(0xFFFF9500)),
  openlist('openlist', 'OpenList', CupertinoIcons.link, Color(0xFF5856D6)),
  quark('quark', '夸克网盘', CupertinoIcons.cloud_fill, Color(0xFF2B6CF5)),
  unknown('', '未知类型', CupertinoIcons.question_circle, Color(0xFF8E8E93));

  final String value;
  final String label;
  final IconData icon;
  final Color color;

  const StorageType(this.value, this.label, this.icon, this.color);

  /// 可在表单中选择的类型
  static List<StorageType> get selectable =>
      values.where((e) => e != unknown).toList();

  /// 是否使用客户端手写表单（D6：已有类型不迁移到按声明渲染）
  bool get hasHandwrittenForm =>
      this == webdav || this == local || this == openlist;

  static StorageType fromString(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) return unknown;
    return values.firstWhere(
      (e) => e != unknown && e.value == normalized,
      orElse: () => unknown,
    );
  }

  static Map<StorageType, List<Storage>> group(List<Storage> storages) {
    final groups = <StorageType, List<Storage>>{};
    for (final type in StorageType.values) {
      final items = storages.where((s) => fromString(s.type) == type).toList();
      if (items.isNotEmpty) groups[type] = items;
    }
    return groups;
  }
}
