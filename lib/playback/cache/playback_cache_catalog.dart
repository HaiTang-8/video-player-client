import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'cache_eviction.dart';

/// 播放缓存的配额范围、默认值与可用平台
abstract final class PlaybackCacheConfig {
  static bool get _mobile => Platform.isIOS || Platform.isAndroid;

  /// 配额上限（GB）；设置里可选的最大值还受剩余空间限制，见 [maxQuotaGbFor]
  static int get maxQuotaGb => _mobile ? 64 : 200;

  /// D2：移动端 2GB、桌面端 10GB
  static int get defaultQuotaGb => _mobile ? 2 : 10;

  /// 0 表示关闭
  static bool isValidQuotaGb(int gb) => gb >= 0 && gb <= maxQuotaGb;

  /// 设置里可选的最大值：已缓存加剩余空间（扣除保留空间）能容纳的整数 GB，不超过 [maxQuotaGb]；
  /// 剩余空间未知时为 [maxQuotaGb]。不低于默认值和当前配额（实际上限另由剩余空间约束）
  static int maxQuotaGbFor({
    required int usedBytes,
    required int? freeBytes,
    required int currentGb,
  }) {
    final fits =
        freeBytes == null
            ? maxQuotaGb
            : effectiveCacheLimit(
                  quotaBytes: maxQuotaGb << 30,
                  usedBytes: usedBytes,
                  freeBytes: freeBytes,
                ) >>
                30;
    return math.max(math.max(fits, defaultQuotaGb), currentGb);
  }

  /// 浏览器里无法监听本机端口，其余平台都经过本机代理和缓存
  static bool get supported => !kIsWeb;
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

  /// 设备剩余空间；查询不到时为 null
  Future<int?> freeBytes();

  /// 按最近访问从新到旧
  Future<List<CachedVideo>> entries();

  Future<void> remove(String id);

  Future<void> clearCache();

  /// 修改配额（0 表示关闭）并按新上限淘汰
  Future<void> setQuota(int bytes);
}
