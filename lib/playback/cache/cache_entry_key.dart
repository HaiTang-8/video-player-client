import 'dart:convert';

import 'package:crypto/crypto.dart';

/// 缓存键：同一个媒体文件在不同签名直链下保持不变
final class CacheEntryKey {
  const CacheEntryKey({
    required this.serverId,
    required this.itemKey,
    this.filePath,
  });

  /// [serverUrl] 只取协议、主机和端口，忽略路径和末尾斜杠
  factory CacheEntryKey.forServer(
    String serverUrl, {
    required String itemKey,
    String? filePath,
  }) {
    final uri = Uri.parse(serverUrl.trim());
    final serverId =
        uri.hasAuthority
            ? '${uri.scheme.toLowerCase()}://${uri.host.toLowerCase()}:${uri.port}'
            : serverUrl.trim().toLowerCase();
    return CacheEntryKey(
      serverId: serverId,
      itemKey: itemKey,
      filePath: filePath,
    );
  }

  final String serverId;

  /// 例如 `movie:12`、`episode:3/4/56`
  final String itemKey;

  /// 片源在存储中的路径（同一集可能有多个片源）
  final String? filePath;

  /// 目录名和代理路径使用的标识
  String get id =>
      sha1
          .convert(utf8.encode(jsonEncode([serverId, itemKey, filePath ?? ''])))
          .toString();

  @override
  bool operator ==(Object other) =>
      other is CacheEntryKey &&
      other.serverId == serverId &&
      other.itemKey == itemKey &&
      other.filePath == filePath;

  @override
  int get hashCode => Object.hash(serverId, itemKey, filePath);
}
