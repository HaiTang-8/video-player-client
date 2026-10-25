import 'package:flutter/cupertino.dart';

import '../../data/models/models.dart';

/// 存储源类型枚举
enum StorageType {
  webdav('webdav', 'WebDAV', CupertinoIcons.cloud, Color(0xFF007AFF)),
  local('local', '本地存储', CupertinoIcons.folder, Color(0xFFFF9500)),
  openlist('openlist', 'OpenList', CupertinoIcons.link, Color(0xFF5856D6));

  final String value;
  final String label;
  final IconData icon;
  final Color color;

  const StorageType(this.value, this.label, this.icon, this.color);

  static StorageType fromString(String value) {
    return StorageType.values.firstWhere(
      (e) => e.value == value.toLowerCase(),
      orElse: () => StorageType.webdav,
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
