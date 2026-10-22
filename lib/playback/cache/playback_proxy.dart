import 'dart:async';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter/widgets.dart';

import 'cache_proxy_server.dart';

/// 本机播放代理的门面（主隔离区）：首次使用时启动代理隔离区，把上游地址登记为本机代理地址
///
/// Stage 2 Spike 只做透传；`--dart-define=PLAYBACK_PROXY=true` 时播放页会经过它
class PlaybackProxy {
  /// [watchLifecycle] 为 true 时回到前台自动检查监听（需要已初始化 WidgetsBinding）
  PlaybackProxy({this.watchLifecycle = true});

  static const devEnabled = bool.fromEnvironment('PLAYBACK_PROXY');

  static final PlaybackProxy instance = PlaybackProxy();

  final bool watchLifecycle;

  final String _token = _randomHex(16);
  Future<_ProxyHandle>? _handle;
  AppLifecycleListener? _lifecycle;
  int _nextId = 0;

  /// 登记上游，返回代理地址；登记在代理隔离区确认后才返回，避免播放器的请求先到
  Future<Uri> register(Uri upstream, Map<String, String> headers) async {
    final handle = await _start();
    final id = '${++_nextId}';
    await handle.call({
      'cmd': 'register',
      'id': id,
      'url': upstream.toString(),
      'headers': headers,
    });
    return Uri.parse('http://127.0.0.1:${handle.port}/$_token/e/$id');
  }

  Future<void> unregister(Uri proxyUri) async {
    final handle = await _handle;
    if (handle == null) return;
    await handle.call({'cmd': 'unregister', 'id': proxyUri.pathSegments.last});
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
    final boot = ReceivePort();
    await Isolate.spawn(
      cacheProxyMain,
      CacheProxyBoot(boot.sendPort, _token),
      debugName: 'playback-proxy',
    );
    final ready = await boot.first as Map;
    boot.close();
    if (watchLifecycle) {
      _lifecycle ??= AppLifecycleListener(
        onResume: () => unawaited(ensureListening()),
      );
    }
    return _ProxyHandle(ready['port'] as int, ready['commands'] as SendPort);
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
}
