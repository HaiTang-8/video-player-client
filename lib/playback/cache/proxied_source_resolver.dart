import '../../data/models/subtitle_info.dart';
import '../../data/services/log_service.dart';
import '../domain/playback_domain.dart';
import '../session/playback_item.dart';
import '../session/playback_source_resolver.dart';
import 'cache_entry_key.dart';
import 'playback_proxy.dart';

/// 网络片源改走本机代理，鉴权头由代理带给上游；本地文件保持原样
///
/// 知道服务器地址时按“服务器 + 媒体 + 文件路径”登记为可缓存条目，签名直链变化不影响命中。
/// 登记的条目到 [dispose] 时才注销：切换剧集时上一个片源可能还有预读请求在路上
class ProxiedSourceResolver implements PlaybackSourceResolver {
  ProxiedSourceResolver(
    this._inner,
    this._proxy, {
    String? Function()? serverUrl,
  }) : _serverUrl = serverUrl;

  /// 用 `--dart-define=PLAYBACK_PROXY=true` 构建时经过本机代理和缓存（设置界面完成前的开关）
  static PlaybackSourceResolver wrapIfEnabled(
    PlaybackSourceResolver inner, {
    String? Function()? serverUrl,
  }) =>
      PlaybackProxy.devEnabled
          ? ProxiedSourceResolver(
            inner,
            PlaybackProxy.instance,
            serverUrl: serverUrl,
          )
          : inner;

  final PlaybackSourceResolver _inner;
  final PlaybackProxy _proxy;
  final String? Function()? _serverUrl;
  final List<Uri> _registered = [];

  @override
  Future<ResolvedPlayback> resolve(PlaybackItem item) async {
    final resolved = await _inner.resolve(item);
    final source = resolved.source;
    if (source.isLocalFile) return resolved;
    final server = _serverUrl?.call();
    final cacheId =
        server == null || server.isEmpty
            ? null
            : CacheEntryKey.forServer(
              server,
              itemKey: _itemKey(item),
              filePath: resolved.filePath,
            ).id;
    final proxied = await _proxy.register(
      Uri.parse(source.url),
      source.httpHeaders,
      cacheId: cacheId,
      refresh: () async {
        final again = await _inner.resolve(item);
        if (again.source.isLocalFile) return null;
        return (
          url: Uri.parse(again.source.url),
          headers: again.source.httpHeaders,
        );
      },
    );
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
