import 'dart:convert';

/// HTTP 相关工具方法
class HttpUtils {
  HttpUtils._();

  /// 生成 Basic Auth 请求头
  static String basicAuthHeader(String username, String password) {
    final token = base64Encode(utf8.encode('$username:$password'));
    return 'Basic $token';
  }

  /// 获取 URI 的有效端口（处理默认端口）
  static int effectivePort(Uri uri) {
    if (uri.hasPort && uri.port > 0) return uri.port;
    switch (uri.scheme.toLowerCase()) {
      case 'https':
        return 443;
      case 'http':
        return 80;
      default:
        return uri.port;
    }
  }

  /// 判断两个 URI 是否同源
  static bool sameOrigin(Uri? a, Uri? b) {
    if (a == null || b == null) return false;
    if (a.scheme.toLowerCase() != b.scheme.toLowerCase()) return false;
    if (a.host.toLowerCase() != b.host.toLowerCase()) return false;
    return effectivePort(a) == effectivePort(b);
  }
}
