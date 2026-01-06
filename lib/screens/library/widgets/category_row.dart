import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/widgets/tap_feedback.dart';
import '../../../core/window/window_controls.dart';
import '../../../data/models/models.dart';
import '../../../providers/providers.dart';
import 'library_poster_card.dart';

/// 单行分类展示（水平滚动）
class CategoryRow extends ConsumerStatefulWidget {
  final CategoryStats category;

  const CategoryRow({required this.category, super.key});

  @override
  ConsumerState<CategoryRow> createState() => _CategoryRowState();
}

class _CategoryRowState extends ConsumerState<CategoryRow> {
  static const double _mobileItemWidth = 88.0;
  static const double _desktopItemWidth = 120.0;
  static const double _itemSpacing = 16.0;
  static const double _horizontalPadding = 16.0;
  static const int _rowCount = 2;

  bool _loaded = false;

  double get _itemWidth =>
      WindowControls.isDesktop ? _desktopItemWidth : _mobileItemWidth;

  @override
  void initState() {
    super.initState();
    // 移动端直接加载默认数量
    if (!WindowControls.isDesktop) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        loadCategoryItems(ref, widget.category.id);
        _loaded = true;
      });
    }
  }

  void _loadForDesktop(double availableWidth) {
    if (_loaded) return;
    _loaded = true;

    final itemsPerRow = ((availableWidth + _itemSpacing) /
            (_itemWidth + _itemSpacing))
        .floor();
    final pageSize = itemsPerRow * _rowCount;

    loadCategoryItems(ref, widget.category.id, pageSize: pageSize);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final itemsState = ref.watch(categoryItemsProvider(widget.category.id));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 分类标题行
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: TapFeedback(
            onTap: () => _navigateToCategory(),
            borderRadius: BorderRadius.circular(8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.category.displayName,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${widget.category.count}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: theme.colorScheme.outline,
                ),
              ],
            ),
          ),
        ),

        // 海报列表
        _buildContent(theme, itemsState),
        const SizedBox(height: 10),
      ],
    );
  }

  Widget _buildContent(ThemeData theme, CategoryItemsState itemsState) {
    if (!WindowControls.isDesktop) {
      if (itemsState.isLoading && itemsState.items.isEmpty) {
        return const SizedBox(
          height: 180,
          child: Center(child: CircularProgressIndicator()),
        );
      }
      if (itemsState.error != null && itemsState.items.isEmpty) {
        return SizedBox(
          height: 180,
          child: Center(
            child:
                Text('加载失败', style: TextStyle(color: theme.colorScheme.error)),
          ),
        );
      }
      if (itemsState.items.isEmpty) {
        return SizedBox(
          height: 180,
          child: Center(
            child:
                Text('暂无内容', style: TextStyle(color: theme.colorScheme.outline)),
          ),
        );
      }
      return _buildHorizontalList(itemsState.items);
    }

    return _buildDesktopGrid(theme, itemsState);
  }

  Widget _buildHorizontalList(List<MediaItem> items) {
    return SizedBox(
      height: 180,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: _horizontalPadding),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          return Padding(
            padding: const EdgeInsets.only(right: _itemSpacing),
            child: LibraryPosterCard(
              item: item,
              width: _mobileItemWidth,
              onTap: () => _navigateToDetail(item),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDesktopGrid(ThemeData theme, CategoryItemsState itemsState) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth - _horizontalPadding * 2;

        // 首次加载时计算需要的数量
        if (!_loaded) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _loadForDesktop(availableWidth);
          });
        }

        if (itemsState.isLoading && itemsState.items.isEmpty) {
          final itemHeight = _itemWidth / 0.48;
          return SizedBox(
            height: itemHeight * _rowCount + _itemSpacing,
            child: const Center(child: CircularProgressIndicator()),
          );
        }
        if (itemsState.error != null && itemsState.items.isEmpty) {
          return SizedBox(
            height: 180,
            child: Center(
              child: Text('加载失败',
                  style: TextStyle(color: theme.colorScheme.error)),
            ),
          );
        }
        if (itemsState.items.isEmpty) {
          return SizedBox(
            height: 180,
            child: Center(
              child: Text('暂无内容',
                  style: TextStyle(color: theme.colorScheme.outline)),
            ),
          );
        }

        final itemsPerRow = ((availableWidth + _itemSpacing) /
                (_itemWidth + _itemSpacing))
            .floor();
        final itemWidth = itemsPerRow > 0
            ? (availableWidth - (itemsPerRow - 1) * _itemSpacing) / itemsPerRow
            : _itemWidth;
        final displayCount =
            (itemsPerRow * _rowCount).clamp(0, itemsState.items.length);
        final itemHeight = itemWidth / 0.48;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: _horizontalPadding),
          child: Wrap(
            spacing: _itemSpacing,
            runSpacing: _itemSpacing,
            children: List.generate(displayCount, (index) {
              final item = itemsState.items[index];
              return SizedBox(
                width: itemWidth,
                height: itemHeight,
                child: LibraryPosterCard(
                  item: item,
                  width: itemWidth,
                  onTap: () => _navigateToDetail(item),
                ),
              );
            }),
          ),
        );
      },
    );
  }

  void _navigateToDetail(MediaItem item) {
    if (item.type == MediaType.movie) {
      context.push('/movie/${item.id}');
    } else {
      context.push('/tvshow/${item.id}');
    }
  }

  void _navigateToCategory() {
    context.push(
      '/category/${widget.category.id}?name=${Uri.encodeComponent(widget.category.displayName)}',
    );
  }
}
