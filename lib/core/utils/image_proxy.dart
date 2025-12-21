/// 图片 URL 处理工具：
/// - 客户端在某些网络环境下可能无法直连 `image.tmdb.org`（即使浏览器能打开也可能失败）。
/// - 为了让客户端访问 TMDB 图片时更稳定，统一走后端 `/api/v1/images/proxy?url=...` 转发。
class ImageProxy {
  /// 判断是否为 TMDB 图片 URL（仅 image.tmdb.org + /t/p/...）
  static bool isTMDBImageUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return false;
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return false;
    final host = uri.host.toLowerCase();
    if (host != 'image.tmdb.org') return false;
    return uri.path.startsWith('/t/p/');
  }

  /// 将 TMDB 图片 URL 转成后端代理 URL；若不满足条件则返回原 URL。
  static String proxyTMDBIfNeeded(String url, String? serverBaseUrl) {
    final origin = url.trim();
    if (origin.isEmpty) return origin;
    final base = serverBaseUrl?.trim();
    if (base == null || base.isEmpty) return origin;
    if (!isTMDBImageUrl(origin)) return origin;

    final baseUri = Uri.tryParse(base);
    if (baseUri == null || !baseUri.hasScheme) return origin;

    final proxy = baseUri.resolve('/api/v1/images/proxy');
    return proxy.replace(queryParameters: {'url': origin}).toString();
  }
}
