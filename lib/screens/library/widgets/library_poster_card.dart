import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../../data/models/models.dart';

/// 媒体库卡片组件（标题在卡片下方）
class LibraryPosterCard extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 海报宽高比 2:3
    final posterHeight = width * 1.5;

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 海报图片
            Container(
              width: width,
              height: posterHeight,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // 海报图片
                    _buildPosterImage(),

                    // 评分角标（右下角）
                    if (item.rating != null && item.rating! > 0)
                      Positioned(
                        bottom: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: _getRatingColor(item.rating!),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            item.rating!.toStringAsFixed(1),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 8),

            // 标题
            Text(
              item.title,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),

            const SizedBox(height: 2),

            // 副标题：电影显示日期，电视剧显示季数
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
    if (item.type == MediaType.movie) {
      // 电影显示上映日期
      if (item.releaseDate != null) {
        return item.releaseDate!.toString().split(' ')[0];
      } else if (item.year != null) {
        return '${item.year}';
      }
      return '';
    } else {
      // 电视剧显示季数
      if (item.numberOfSeasons != null && item.numberOfSeasons! > 0) {
        return '共${item.numberOfSeasons}季';
      } else if (item.year != null) {
        return '${item.year}';
      }
      return '';
    }
  }

  Widget _buildPosterImage() {
    if (item.posterPath != null && item.posterPath!.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: item.posterPath!,
        fit: BoxFit.cover,
        placeholder: (context, url) => _buildPlaceholder(),
        errorWidget: (context, url, error) => _buildPlaceholder(),
      );
    }
    return _buildPlaceholder();
  }

  Widget _buildPlaceholder() {
    return Container(
      color: Colors.grey[300],
      child: const Center(
        child: Icon(
          Icons.movie_outlined,
          size: 40,
          color: Colors.grey,
        ),
      ),
    );
  }
}
