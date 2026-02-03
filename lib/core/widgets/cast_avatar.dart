import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../data/services/log_service.dart';
import '../utils/image_proxy.dart';

/// 演员头像组件：
/// - 对 TMDB 图片（image.tmdb.org）统一改为走后端 `/api/v1/images/proxy?url=...` 转发，避免客户端直连失败。
class CastAvatar extends StatelessWidget {
  final String? imageUrl;
  final String? serverBaseUrl;
  final double size;
  final double iconSize;
  final Color iconColor;

  const CastAvatar({
    super.key,
    required this.size,
    this.imageUrl,
    this.serverBaseUrl,
    this.iconSize = 32,
    this.iconColor = Colors.white70,
  });

  Widget _buildFallbackIcon() {
    return Icon(Icons.person, color: iconColor, size: iconSize);
  }

  @override
  Widget build(BuildContext context) {
    final origin = imageUrl?.trim();
    if (origin == null || origin.isEmpty) {
      return _buildFallbackIcon();
    }

    final proxied = ImageProxy.proxyTMDBIfNeeded(origin, serverBaseUrl);

    return CachedNetworkImage(
      imageUrl: proxied,
      width: size,
      height: size,
      fit: BoxFit.cover,
      placeholder: (_, __) => _buildFallbackIcon(),
      errorWidget: (_, __, error) {
        // 图片加载失败一般不影响主流程，按 debug 级别记录，避免在 release 下刷屏。
        LogService.instance.debug('CastAvatar', 'load failed: $proxied, error: $error');

        return _buildFallbackIcon();
      },
    );
  }
}
