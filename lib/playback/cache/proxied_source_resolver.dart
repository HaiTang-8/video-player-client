import 'dart:async';

import '../../data/models/subtitle_info.dart';
import '../../data/services/log_service.dart';
import '../domain/playback_domain.dart';
import '../session/playback_item.dart';
import '../session/playback_source_resolver.dart';
import 'cache_entry_key.dart';
import 'playback_cache_catalog.dart';
import 'playback_proxy.dart';

/// 网络片源改走本机代理，鉴权头由代理带给上游；本地文件保持原样
///
/// 知道服务器地址时按“服务器 + 媒体 + 文件路径”登记为可缓存条目，签名直链变化不影响命中。
/// 这部片子已有缓存时直接返回代理地址，流地址 API 和 302 解析放到后台，完成后再交给代理。
/// 登记的条目到 [dispose] 时才注销：切换剧集时上一个片源可能还有预读请求在路上
class ProxiedSourceResolver implements PlaybackSourceResolver {
  ProxiedSourceResolver(
    this._inner,
    this._proxy, {
    String? Function()? serverUrl,
    Future<String?> Function(PlaybackItem item)? findDownloadedFile,
  }) : _serverUrl = serverUrl,
       _findDownloadedFile = findDownloadedFile;

  /// 支持的平台上、配额不为 0 时经过本机代理和缓存；否则直连
  static PlaybackSourceResolver wrapIfEnabled(
    PlaybackSourceResolver inner, {
    required int quotaGb,
    String? Function()? serverUrl,
    Future<String?> Function(PlaybackItem item)? findDownloadedFile,
  }) {
    if (!PlaybackCacheConfig.supported || quotaGb <= 0) return inner;
    final proxy = PlaybackProxy.instance;
    unawaited(proxy.setQuota(quotaGb << 30));
    return ProxiedSourceResolver(
      inner,
      proxy,
      serverUrl: serverUrl,
      findDownloadedFile: findDownloadedFile,
    );
  }

  final PlaybackSourceResolver _inner;
  final PlaybackProxy _proxy;
  final String? Function()? _serverUrl;
  final Future<String?> Function(PlaybackItem item)? _findDownloadedFile;
  final List<Uri> _registered = [];

  @override
  Future<ResolvedPlayback> resolve(PlaybackItem item) async {
    final server = _serverUrl?.call();
    final itemKey = _itemKey(item);
    if (server != null &&
        server.isNotEmpty &&
        await _findDownloadedFile?.call(item) == null) {
      final key = CacheEntryKey.forServer(server, itemKey: itemKey);
      final hit = await _proxy.lookup(key.serverId, itemKey);
      if (hit != null) return _resolveFromCache(item, key, hit);
    }

    final resolved = await _inner.resolve(item);
    final source = resolved.source;
    if (source.isLocalFile) return resolved;
    final key =
        server == null || server.isEmpty
            ? null
            : CacheEntryKey.forServer(
              server,
              itemKey: itemKey,
              filePath: resolved.filePath,
            );
    final proxied = await _proxy.register(
      Uri.parse(source.url),
      source.httpHeaders,
      cacheId: key?.id,
      filePath: resolved.filePath,
      storageId: resolved.storageId,
      serverId: key?.serverId,
      itemKey: itemKey,
      refresh: _refresher(item),
    );
    final cacheId = key?.id;
    _registered.add(proxied);
    LogService.instance.info(
      'PlaybackProxy',
      'via proxy: $proxied${cacheId == null ? '' : ' cache=$cacheId'}',
    );
    return ResolvedPlayback(
      PlaybackSource.network(proxied.toString()),
      storageId: resolved.storageId,
      filePath: resolved.filePath,
      observer: _ProxyObserver(_proxy, proxied),
    );
  }

  /// 命中缓存：先用缓存里记下的片源信息登记，后台再解析上游地址
  Future<ResolvedPlayback> _resolveFromCache(
    PlaybackItem item,
    CacheEntryKey key,
    CacheHit hit,
  ) async {
    final proxied = await _proxy.register(
      null,
      const {},
      cacheId: hit.cacheId,
      filePath: hit.filePath,
      storageId: hit.storageId,
      serverId: key.serverId,
      itemKey: key.itemKey,
      refresh: _refresher(item),
    );
    _registered.add(proxied);
    LogService.instance.info(
      'PlaybackProxy',
      'from cache: $proxied cache=${hit.cacheId}',
    );
    unawaited(_resolveUpstream(item, key, hit.cacheId, proxied));
    return ResolvedPlayback(
      PlaybackSource.network(proxied.toString()),
      storageId: hit.storageId,
      filePath: hit.filePath,
      observer: _ProxyObserver(_proxy, proxied),
    );
  }

  /// 后台解析上游地址交给代理。片源换了（文件路径变化）时作废旧缓存，需要回源的请求随之失败
  Future<void> _resolveUpstream(
    PlaybackItem item,
    CacheEntryKey key,
    String cacheId,
    Uri proxied,
  ) async {
    try {
      final resolved = await _inner.resolve(item);
      if (resolved.source.isLocalFile) {
        _proxy.failUpstream(proxied);
        return;
      }
      final current =
          CacheEntryKey.forServer(
            key.serverId,
            itemKey: key.itemKey,
            filePath: resolved.filePath,
          ).id;
      if (current != cacheId) {
        LogService.instance.warn(
          'PlaybackProxy',
          'source changed, dropping cache $cacheId',
        );
        await _proxy.remove(cacheId);
        _proxy.failUpstream(proxied);
        return;
      }
      _proxy.provideUpstream(
        proxied,
        Uri.parse(resolved.source.url),
        resolved.source.httpHeaders,
      );
    } catch (e) {
      LogService.instance.warn(
        'PlaybackProxy',
        'background resolve failed, serving cache only: $e',
      );
      _proxy.failUpstream(proxied);
    }
  }

  UpstreamRefresher _refresher(PlaybackItem item) => () async {
    final again = await _inner.resolve(item);
    if (again.source.isLocalFile) return null;
    return (
      url: Uri.parse(again.source.url),
      headers: again.source.httpHeaders,
    );
  };

  @override
  Future<String?> fetchSubtitleText(SubtitleInfo subtitle) =>
      _inner.fetchSubtitleText(subtitle);

  @override
  void dispose() {
    if (_registered.isNotEmpty) {
      _proxy.stats().then(
        (stats) => LogService.instance.info('PlaybackProxy', 'stats: $stats'),
      );
    }
    for (final uri in _registered) {
      _proxy.unregister(uri);
    }
    _registered.clear();
    _inner.dispose();
  }

  static String _itemKey(PlaybackItem item) => switch (item) {
    MoviePlaybackItem(:final movieId) => 'movie:$movieId',
    EpisodePlaybackItem(:final tvShowId, :final seasonId, :final episodeId) =>
      'episode:$tvShowId/$seasonId/$episodeId',
  };
}

class _ProxyObserver implements PlaybackSourceObserver {
  _ProxyObserver(this._proxy, this._uri);

  final PlaybackProxy _proxy;
  final Uri _uri;

  @override
  void onOpening(Duration? startAt) => _proxy.opening(_uri, startAt);

  @override
  void onFirstFrame() => _proxy.opened(_uri);

  @override
  void onSeek(Duration position) => _proxy.seek(_uri, position);

  @override
  void onProgress(Duration position, Duration duration) =>
      _proxy.progress(_uri, position, duration);
}
