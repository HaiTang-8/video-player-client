import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import 'cache_proxy_server.dart';
import 'playback_cache_catalog.dart';

/// 重新解析上游地址（签名直链过期时由代理请求）；拿不到时返回 null
typedef UpstreamRefresher =
    Future<({Uri url, Map<String, String> headers})?> Function();

/// 按媒体查找到的缓存条目
typedef CacheHit = ({String cacheId, String? filePath, int? storageId});

/// 本机播放代理的门面（主隔离区）：首次使用时启动代理隔离区，把上游地址登记为本机代理地址；
/// 提供缓存目录时，可缓存的条目经过磁盘缓存
///
/// 播放页经 [ProxiedSourceResolver.wrapIfEnabled] 接入，是否启用见 [PlaybackCacheConfig.supported] 和播放设置里的配额
class PlaybackProxy implements PlaybackCacheCatalog {
  /// [watchLifecycle] 为 true 时回到前台检查监听、进入后台保存缓存元数据（需要已初始化 WidgetsBinding）
  PlaybackProxy({
    this.watchLifecycle = true,
    this.cacheDirectory,
    int? quotaBytes,
    this.freeSpace,
    this.blockSize = 4 << 20,
  }) : _quotaBytes = quotaBytes ?? defaultQuotaBytes;

  static final PlaybackProxy instance = PlaybackProxy(
    cacheDirectory: defaultCacheDirectory,
    freeSpace: platformFreeSpace,
  );

  static int get defaultQuotaBytes => PlaybackCacheConfig.defaultQuotaGb << 30;

  static Future<Directory?> defaultCacheDirectory() async => Directory(
    '${(await getApplicationCacheDirectory()).path}/playback_cache',
  );

  /// iOS / Android 通过存储通道查询；桌面端没有接口，返回 null（只按配额）
  static Future<int?> platformFreeSpace() async {
    if (!(Platform.isIOS || Platform.isAndroid)) return null;
    try {
      final value = await const MethodChannel(
        'media_player/storage',
      ).invokeMethod<num>('getAvailableSpace');
      return value?.toInt();
    } catch (_) {
      return null;
    }
  }

  final bool watchLifecycle;
  final Future<Directory?> Function()? cacheDirectory;
  final Future<int?> Function()? freeSpace;
  final int blockSize;
  int _quotaBytes;

  final String _token = _randomHex(16);
  final Map<String, UpstreamRefresher> _refreshers = {};
  Future<_ProxyHandle>? _handle;
  AppLifecycleListener? _lifecycle;
  DateTime? _limitsSentAt;
  int _nextId = 0;

  /// 登记上游，返回代理地址；登记在代理隔离区确认后才返回，避免播放器的请求先到。
  /// 给出 [cacheId] 时经过磁盘缓存；[refresh] 用于上游返回 401 / 403 / 410 时重新解析。
  /// [upstream] 为空时（命中缓存、后台还在解析）已缓存的部分照常读取，回源要等 [provideUpstream]
  Future<Uri> register(
    Uri? upstream,
    Map<String, String> headers, {
    String? cacheId,
    UpstreamRefresher? refresh,
    String? filePath,
    int? storageId,
    String? serverId,
    String? itemKey,
  }) async {
    final handle = await _start();
    final id = 'r${++_nextId}';
    if (refresh != null) _refreshers[id] = refresh;
    await handle.call({
      'cmd': 'register',
      'id': id,
      'url': upstream?.toString(),
      'headers': headers,
      'cacheId': cacheId,
      'refreshable': refresh != null,
      'filePath': filePath,
      'storageId': storageId,
      'serverId': serverId,
      'itemKey': itemKey,
    });
    if (DateTime.now().difference(_limitsSentAt ?? DateTime(2000)) >
        const Duration(minutes: 1)) {
      await _sendLimits(handle);
    }
    return Uri.parse('http://127.0.0.1:${handle.port}/$_token/e/$id');
  }

  /// 这部片子最近使用的缓存条目；没有缓存或不在支持的平台时返回 null
  Future<CacheHit?> lookup(String serverId, String itemKey) async {
    final handle = await _start();
    final found =
        await handle.call({
              'cmd': 'lookup',
              'serverId': serverId,
              'itemKey': itemKey,
            })
            as Map?;
    if (found == null) return null;
    return (
      cacheId: found['cacheId'] as String,
      filePath: found['filePath'] as String?,
      storageId: found['storageId'] as int?,
    );
  }

  /// 补上后台解析出的上游地址，等待中的回源请求随之继续
  void provideUpstream(Uri proxyUri, Uri url, Map<String, String> headers) =>
      _post(proxyUri, {
        'cmd': 'upstream',
        'url': url.toString(),
        'headers': headers,
      });

  /// 后台解析失败：需要回源的请求返回 502，已缓存的部分照常读取
  void failUpstream(Uri proxyUri) => _post(proxyUri, {'cmd': 'upstreamFailed'});

  Future<void> unregister(Uri proxyUri) async {
    final handle = await _handle;
    final id = proxyUri.pathSegments.last;
    _refreshers.remove(id);
    if (handle == null) return;
    await handle.call({'cmd': 'unregister', 'id': id});
  }

  /// 开始打开：之后的文件首尾读取记为固定区间，起播位置与下一次读取的偏移配对
  void opening(Uri proxyUri, Duration? startAt) => _post(proxyUri, {
    'cmd': 'opening',
    'positionMs': startAt?.inMilliseconds,
  });

  /// 第一帧已上屏，打开阶段结束
  void opened(Uri proxyUri) => _post(proxyUri, {'cmd': 'opened'});

  void seek(Uri proxyUri, Duration position) =>
      _post(proxyUri, {'cmd': 'seek', 'positionMs': position.inMilliseconds});

  void progress(Uri proxyUri, Duration position, Duration duration) =>
      _post(proxyUri, {
        'cmd': 'progress',
        'positionMs': position.inMilliseconds,
        'durationMs': duration.inMilliseconds,
      });

  /// 修改配额（0 表示只透传、不写盘）并按新上限淘汰
  @override
  Future<void> setQuota(int bytes) async {
    _quotaBytes = bytes;
    final handle = await _handle;
    if (handle != null) await _sendLimits(handle);
  }

  Future<Map<String, int>> usage() async {
    final handle = await _start();
    return Map<String, int>.from(await handle.call({'cmd': 'usage'}) as Map);
  }

  @override
  Future<void> clearCache() async {
    final handle = await _start();
    await handle.call({'cmd': 'clear'});
  }

  @override
  Future<int> usedBytes() async => (await usage())['bytes'] ?? 0;

  @override
  Future<List<CachedVideo>> entries() async {
    final handle = await _start();
    final list = await handle.call({'cmd': 'entries'}) as List;
    return [
      for (final item in list.cast<Map>())
        CachedVideo(
          id: item['id'] as String,
          name: _fileName(item['filePath'] as String?) ?? item['id'] as String,
          cachedBytes: item['cachedBytes'] as int,
          sizeBytes: item['size'] as int,
          lastAccess: DateTime.fromMillisecondsSinceEpoch(
            item['lastAccess'] as int,
          ),
        ),
    ];
  }

  @override
  Future<void> remove(String id) async {
    final handle = await _start();
    await handle.call({'cmd': 'remove', 'cacheId': id});
  }

  static String? _fileName(String? path) {
    if (path == null || path.isEmpty) return null;
    final name = path
        .split(RegExp(r'[/\\]'))
        .lastWhere((s) => s.isNotEmpty, orElse: () => '');
    return name.isEmpty ? null : name;
  }

  /// 立即保存缓存元数据
  Future<void> flush() async {
    final handle = await _handle;
    if (handle != null) await handle.call({'cmd': 'flush'});
  }

  /// 监听失效时在同一端口重新绑定；回到前台时自动调用
  Future<bool> ensureListening() async {
    final handle = await _handle;
    if (handle == null) return true;
    return await handle.call({'cmd': 'ensure'}) as bool;
  }

  Future<Map<String, int>> stats() async {
    final handle = await _start();
    return Map<String, int>.from(await handle.call({'cmd': 'stats'}) as Map);
  }

  /// 模拟系统回收监听 socket，只用于测试
  @visibleForTesting
  Future<void> debugCloseListener() async {
    final handle = await _start();
    await handle.call({'cmd': 'closeListener'});
  }

  Future<_ProxyHandle> _start() => _handle ??= _spawn();

  Future<_ProxyHandle> _spawn() async {
    final directory = await cacheDirectory?.call();
    final events = ReceivePort()..listen(_onEvent);
    final boot = ReceivePort();
    await Isolate.spawn(
      cacheProxyMain,
      CacheProxyBoot(
        boot.sendPort,
        _token,
        events: events.sendPort,
        cacheRoot: directory?.path,
        blockSize: blockSize,
      ),
      debugName: 'playback-proxy',
    );
    final ready = await boot.first as Map;
    boot.close();
    final handle = _ProxyHandle(
      ready['port'] as int,
      ready['commands'] as SendPort,
    );
    await _sendLimits(handle);
    if (watchLifecycle) {
      _lifecycle ??= AppLifecycleListener(
        onResume: () => unawaited(ensureListening()),
        onPause: () => unawaited(flush()),
      );
    }
    return handle;
  }

  Future<void> _sendLimits(_ProxyHandle handle) async {
    _limitsSentAt = DateTime.now();
    await handle.call({
      'cmd': 'limits',
      'quotaBytes': _quotaBytes,
      'freeBytes': await freeSpace?.call(),
    });
  }

  Future<void> _onEvent(Object? message) async {
    final map = message as Map;
    if (map['event'] != 'refresh') return;
    final reply = map['reply'] as SendPort;
    try {
      final result = await _refreshers[map['id']]?.call();
      reply.send(
        result == null
            ? null
            : {'url': result.url.toString(), 'headers': result.headers},
      );
    } catch (_) {
      reply.send(null);
    }
  }

  void _post(Uri proxyUri, Map<String, Object?> message) {
    final handle = _handle;
    if (handle == null) return;
    unawaited(
      handle.then(
        (h) => h.post({...message, 'id': proxyUri.pathSegments.last}),
      ),
    );
  }

  static String _randomHex(int length) {
    final random = Random.secure();
    return List.generate(
      length,
      (_) => random.nextInt(16).toRadixString(16),
    ).join();
  }
}

class _ProxyHandle {
  _ProxyHandle(this.port, this._commands);

  final int port;
  final SendPort _commands;

  Future<Object?> call(Map<String, Object?> message) async {
    final reply = ReceivePort();
    _commands.send({...message, 'reply': reply.sendPort});
    final result = await reply.first;
    reply.close();
    return result;
  }

  void post(Map<String, Object?> message) => _commands.send(message);
}
