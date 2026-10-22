import '../../data/models/subtitle_info.dart';
import '../../data/services/log_service.dart';
import '../domain/playback_domain.dart';
import '../session/playback_item.dart';
import '../session/playback_source_resolver.dart';
import 'playback_proxy.dart';

/// 网络片源改走本机代理，鉴权头由代理带给上游；本地文件保持原样
///
/// 登记的条目到 [dispose] 时才注销：切换剧集时上一个片源可能还有预读请求在路上
class ProxiedSourceResolver implements PlaybackSourceResolver {
  ProxiedSourceResolver(this._inner, this._proxy);

  /// 用 `--dart-define=PLAYBACK_PROXY=true` 构建时经过本机代理（Stage 2 真机验证用）
  static PlaybackSourceResolver wrapIfEnabled(PlaybackSourceResolver inner) =>
      PlaybackProxy.devEnabled
          ? ProxiedSourceResolver(inner, PlaybackProxy.instance)
          : inner;

  final PlaybackSourceResolver _inner;
  final PlaybackProxy _proxy;
  final List<Uri> _registered = [];

  @override
  Future<ResolvedPlayback> resolve(PlaybackItem item) async {
    final resolved = await _inner.resolve(item);
    final source = resolved.source;
    if (source.isLocalFile) return resolved;
    final proxied = await _proxy.register(
      Uri.parse(source.url),
      source.httpHeaders,
    );
    _registered.add(proxied);
    LogService.instance.info('PlaybackProxy', 'via proxy: $proxied');
    return ResolvedPlayback(
      PlaybackSource.network(proxied.toString()),
      storageId: resolved.storageId,
      filePath: resolved.filePath,
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
}
