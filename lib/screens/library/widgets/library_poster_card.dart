import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/widgets/tap_feedback.dart';
import '../../../data/models/models.dart';
import '../../../core/utils/image_proxy.dart';
import '../../../providers/server_provider.dart';

/// 媒体库卡片组件（标题在卡片下方）
class LibraryPosterCard extends ConsumerStatefulWidget {
  final MediaItem item;
  final VoidCallback? onTap;
  final double width;

  const LibraryPosterCard({
    super.key,
    required this.item,
    this.onTap,
    this.width = 140,
  });

  @override
  ConsumerState<LibraryPosterCard> createState() => _LibraryPosterCardState();
}

class _LibraryPosterCardState extends ConsumerState<LibraryPosterCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final serverBaseUrl = ref.watch(serverUrlProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        final actualWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : widget.width;
        final hasFiniteHeight = constraints.maxHeight.isFinite;
        final posterHeight = actualWidth * 1.5;

        Widget posterWidget = AnimatedScale(
          scale: _isHovered ? 1.03 : 1.0,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: actualWidth,
            height: hasFiniteHeight ? null : posterHeight,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha: _isHovered ? 0.3 : 0.15,
                  ),
                  blurRadius: _isHovered ? 16 : 8,
                  offset: Offset(0, _isHovered ? 8 : 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildPosterImage(serverBaseUrl),
                  if (widget.item.rating != null && widget.item.rating! > 0)
                    Positioned(
                      bottom: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: _getRatingColor(widget.item.rating!),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          widget.item.rating!.toStringAsFixed(1),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );

        if (hasFiniteHeight) {
          posterWidget = Expanded(
            child: AspectRatio(
              aspectRatio: 2 / 3,
              child: posterWidget,
            ),
          );
        }

        return MouseRegion(
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          cursor: SystemMouseCursors.click,
          child: TapFeedback(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: actualWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: hasFiniteHeight ? MainAxisSize.max : MainAxisSize.min,
                children: [
                  posterWidget,
                  const SizedBox(height: 8),
                  Text(
                    widget.item.title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _getSubtitle(),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// 根据评分获取颜色
  Color _getRatingColor(double rating) {
    if (rating >= 8.0) {
      return Colors.green.shade600;
    } else if (rating >= 6.0) {
      return Colors.orange.shade600;
    } else {
      return Colors.grey.shade600;
    }
  }

  /// 获取副标题
  String _getSubtitle() {
    if (widget.item.type == MediaType.movie) {
      // 电影显示上映日期
      if (widget.item.releaseDate != null) {
        return widget.item.releaseDate!.toString().split(' ')[0];
      } else if (widget.item.year != null) {
        return '${widget.item.year}';
      }
      return '';
    } else {
      // 电视剧显示季数
      if (widget.item.numberOfSeasons != null &&
          widget.item.numberOfSeasons! > 0) {
        return '共${widget.item.numberOfSeasons}季';
      } else if (widget.item.year != null) {
        return '${widget.item.year}';
      }
      return '';
    }
  }

  Widget _buildPosterImage(String? serverBaseUrl) {
    if (widget.item.posterPath != null && widget.item.posterPath!.isNotEmpty) {
      final posterUrl = ImageProxy.proxyTMDBIfNeeded(
        widget.item.posterPath!,
        serverBaseUrl,
      );
      return CachedNetworkImage(
        imageUrl: posterUrl,
        fit: BoxFit.cover,
        placeholder: (context, url) => _buildPlaceholder(),
        errorWidget: (context, url, error) => _buildPlaceholder(),
      );
    }
    return _buildPlaceholder();
  }

  Widget _buildPlaceholder() {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(Icons.movie_outlined, size: 40, color: theme.colorScheme.outline),
      ),
    );
  }
}
