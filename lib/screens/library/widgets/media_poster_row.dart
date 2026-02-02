import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;
import '../../../core/widgets/tap_feedback.dart';
import '../../../core/window/window_controls.dart';
import '../../../data/models/models.dart';
import 'library_poster_card.dart';

class MediaPosterRow extends ConsumerWidget {
  final String title;
  final int? count;
  final IconData? icon;
  final Color? iconColor;
  final VoidCallback? onTitleTap;

  final List<MediaItem> items;
  final bool isLoading;
  final String? error;
  final VoidCallback? onRetry;

  final void Function(MediaItem)? onItemTap;
  final String itemKeyPrefix;

  final bool useDesktopGrid;
  final int desktopRowCount;

  final Widget Function(int index, double width)? itemBuilder;
  final int? itemCount;

  static const double mobileItemWidth = 88.0;
  static const double desktopItemWidth = 120.0;
  static const double itemSpacing = 16.0;
  static const double horizontalPadding = 16.0;

  const MediaPosterRow({
    super.key,
    required this.title,
    this.count,
    this.icon,
    this.iconColor,
    this.onTitleTap,
    this.items = const [],
    this.isLoading = false,
    this.error,
    this.onRetry,
    this.onItemTap,
    this.itemKeyPrefix = 'poster',
    this.useDesktopGrid = false,
    this.desktopRowCount = 2,
    this.itemBuilder,
    this.itemCount,
  });

  double get _itemWidth =>
      WindowControls.isDesktop ? desktopItemWidth : mobileItemWidth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildTitleRow(theme),
        _buildContent(context, theme),
        const SizedBox(height: 10),
      ],
    );
  }

  Widget _buildTitleRow(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: TapFeedback(
        onTap: onTitleTap,
        borderRadius: BorderRadius.circular(8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 20, color: iconColor ?? theme.colorScheme.primary),
              const SizedBox(width: 8),
            ],
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            if (count != null) ...[
              const SizedBox(width: 6),
              Text(
                '$count',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
            Icon(
              Icons.chevron_right,
              size: 18,
              color: theme.colorScheme.outline,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, ThemeData theme) {
    final textScaler = MediaQuery.textScalerOf(context);
    final posterHeight = _itemWidth * 1.5;
    final listHeight = posterHeight + 8 + textScaler.scale(40);
    final actualItemCount = itemCount ?? items.length;

    if (!WindowControls.isDesktop || !useDesktopGrid) {
      if (isLoading && actualItemCount == 0) {
        return SizedBox(
          height: listHeight,
          child: const Center(child: CircularProgressIndicator()),
        );
      }
      if (error != null && actualItemCount == 0) {
        return SizedBox(
          height: listHeight,
          child: Center(child: _buildInlineError(shadcn.Theme.of(context))),
        );
      }
      if (actualItemCount == 0) {
        return SizedBox(
          height: listHeight,
          child: Center(
            child: Text('暂无内容', style: TextStyle(color: theme.colorScheme.outline)),
          ),
        );
      }
      return _buildHorizontalList(listHeight, actualItemCount);
    }

    return _buildDesktopGrid(context, theme, actualItemCount);
  }

  Widget _buildHorizontalList(double listHeight, int actualItemCount) {
    return SizedBox(
      height: listHeight,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: horizontalPadding),
        itemCount: actualItemCount,
        itemBuilder: (context, index) {
          if (itemBuilder != null) {
            return Padding(
              padding: const EdgeInsets.only(right: itemSpacing),
              child: itemBuilder!(index, _itemWidth),
            );
          }
          final item = items[index];
          return Padding(
            padding: const EdgeInsets.only(right: itemSpacing),
            child: LibraryPosterCard(
              key: ValueKey('${itemKeyPrefix}_${item.type.name}_${item.id}'),
              item: item,
              width: _itemWidth,
              onTap: onItemTap != null ? () => onItemTap!(item) : null,
            ),
          );
        },
      ),
    );
  }

  Widget _buildDesktopGrid(BuildContext context, ThemeData theme, int actualItemCount) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth - horizontalPadding * 2;
        final itemHeight = _itemWidth / 0.48;

        if (isLoading && actualItemCount == 0) {
          return SizedBox(
            height: itemHeight * desktopRowCount + itemSpacing,
            child: const Center(child: CircularProgressIndicator()),
          );
        }
        if (error != null && actualItemCount == 0) {
          return SizedBox(
            height: 180,
            child: Center(child: _buildInlineError(shadcn.Theme.of(context))),
          );
        }
        if (actualItemCount == 0) {
          return SizedBox(
            height: 180,
            child: Center(
              child: Text('暂无内容', style: TextStyle(color: theme.colorScheme.outline)),
            ),
          );
        }

        final itemsPerRow = ((availableWidth + itemSpacing) /
                (_itemWidth + itemSpacing))
            .floor()
            .clamp(1, 100);
        final itemWidth =
            (availableWidth - (itemsPerRow - 1) * itemSpacing) / itemsPerRow;
        final displayCount =
            (itemsPerRow * desktopRowCount).clamp(0, actualItemCount);
        final actualItemHeight = itemWidth / 0.48;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: horizontalPadding),
          child: Wrap(
            spacing: itemSpacing,
            runSpacing: itemSpacing,
            children: List.generate(displayCount, (index) {
              if (itemBuilder != null) {
                return SizedBox(
                  width: itemWidth,
                  height: actualItemHeight,
                  child: itemBuilder!(index, itemWidth),
                );
              }
              final item = items[index];
              return SizedBox(
                width: itemWidth,
                height: actualItemHeight,
                child: LibraryPosterCard(
                  key: ValueKey('${itemKeyPrefix}_${item.type.name}_${item.id}'),
                  item: item,
                  width: itemWidth,
                  onTap: onItemTap != null ? () => onItemTap!(item) : null,
                ),
              );
            }),
          ),
        );
      },
    );
  }

  Widget _buildInlineError(shadcn.ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: theme.colorScheme.destructive.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            shadcn.LucideIcons.circleAlert,
            size: 24,
            color: theme.colorScheme.destructive,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '加载失败',
          style: theme.typography.small.copyWith(
            color: theme.colorScheme.mutedForeground,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 12),
        if (onRetry != null)
          shadcn.OutlineButton(
            onPressed: onRetry,
            size: shadcn.ButtonSize.small,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(shadcn.LucideIcons.refreshCw, size: 14),
                const SizedBox(width: 6),
                const Text('重试'),
              ],
            ),
          ),
      ],
    );
  }
}
