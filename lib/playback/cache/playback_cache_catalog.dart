import 'dart:io';

/// 播放缓存的配额选项、默认值与可用平台
abstract final class PlaybackCacheConfig {
  /// 0 表示关闭
  static const quotaOptionsGb = [0, 1, 2, 5, 10, 20];

  /// D2：移动端 2GB、桌面端 10GB
  static int get defaultQuotaGb =>
      Platform.isIOS || Platform.isAndroid ? 2 : 10;

  /// 只在已验证的平台（iOS）经过代理和缓存；其他平台推广前可用 `--dart-define=PLAYBACK_PROXY=true` 强制开启。
  /// macOS 的 Release 构建缺少 network.server 权限，代理无法监听
  static bool get supported =>
      Platform.isIOS || const bool.fromEnvironment('PLAYBACK_PROXY');
}

/// 缓存明细页的一条记录
final class CachedVideo {
  const CachedVideo({
    required this.id,
    required this.name,
    required this.cachedBytes,
    required this.sizeBytes,
    required this.lastAccess,
  });

  final String id;

  /// 文件名；没有时为媒体标识
  final String name;
  final int cachedBytes;
  final int sizeBytes;
  final DateTime lastAccess;

  bool get complete => sizeBytes > 0 && cachedBytes >= sizeBytes;
}

/// 设置页、缓存明细页和存储管理页读取与管理播放缓存的接口
abstract interface class PlaybackCacheCatalog {
  Future<int> usedBytes();

  /// 按最近访问从新到旧
  Future<List<CachedVideo>> entries();

  Future<void> remove(String id);

  Future<void> clearCache();

  /// 修改配额（0 表示关闭）并按新上限淘汰
  Future<void> setQuota(int bytes);
}
