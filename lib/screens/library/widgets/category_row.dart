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
  String? _loadedServerUrl;

  double get _itemWidth =>
      WindowControls.isDesktop ? _desktopItemWidth : _mobileItemWidth;

  @override
  void initState() {
    super.initState();
    // 移动端直接加载默认数量（避免首帧“暂无内容”闪烁）。
    if (!WindowControls.isDesktop) {
      _tryLoad();
    }
  }

  void _tryLoad({int? pageSize}) {
    final serverUrl = ref.read(serverUrlProvider);
    final service = ref.read(mediaServiceProvider);
    if (serverUrl == null || serverUrl.isEmpty || service == null) return;

    // Treat "loaded" as scoped to current serverUrl; switching server should reload.
    if (_loaded && _loadedServerUrl == serverUrl) return;
    _loaded = true;
    _loadedServerUrl = serverUrl;
    loadCategoryItems(ref, widget.category.id, pageSize: pageSize ?? 20);
  }

  void _retry() {
    _loaded = false;
    _loadedServerUrl = null;
    if (WindowControls.isDesktop) {
      setState(() {});
    } else {
      _tryLoad();
    }
  }

  void _loadForDesktop(double availableWidth) {
    final itemsPerRow = ((availableWidth + _itemSpacing) /
            (_itemWidth + _itemSpacing))
        .floor()
        .clamp(1, 100);
    final pageSize = itemsPerRow * _rowCount;
    _tryLoad(pageSize: pageSize);
  }

  @override
  Widget build(BuildContext context) {
    // Server switch: clear local "loaded" flag so the row can reload on the new server.
    ref.listen<String?>(serverUrlProvider, (previous, next) {
      if (previous == next) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _loaded = false;
        _loadedServerUrl = null;
        // On desktop the pageSize depends on layout; trigger a rebuild to recompute.
        if (WindowControls.isDesktop) {
          setState(() {});
        } else {
          _tryLoad();
        }
      });
    });

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
    final textScaler = MediaQuery.textScalerOf(context);
    final mobileListHeight = 132 + 8 + textScaler.scale(40);

    if (!WindowControls.isDesktop) {
      if (!_loaded && itemsState.items.isEmpty && itemsState.error == null) {
        // Initial load (or server switched) – show loading instead of "empty" flash.
        return SizedBox(
          height: mobileListHeight,
          child: const Center(child: CircularProgressIndicator()),
        );
      }
      if (itemsState.isLoading && itemsState.items.isEmpty) {
        return SizedBox(
          height: mobileListHeight,
          child: const Center(child: CircularProgressIndicator()),
        );
      }
      if (itemsState.error != null && itemsState.items.isEmpty) {
        return SizedBox(
          height: mobileListHeight,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('加载失败', style: TextStyle(color: theme.colorScheme.error)),
                const SizedBox(height: 8),
                TextButton(onPressed: _retry, child: const Text('重试')),
              ],
            ),
          ),
        );
      }
      if (itemsState.items.isEmpty) {
        return SizedBox(
          height: mobileListHeight,
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
    final textScaler = MediaQuery.textScalerOf(context);
    final listHeight = 132 + 8 + textScaler.scale(40);

    return SizedBox(
      height: listHeight,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: _horizontalPadding),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          return Padding(
            padding: const EdgeInsets.only(right: _itemSpacing),
            child: LibraryPosterCard(
              key: ValueKey('poster_${item.type.name}_${item.id}'),
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
            if (!mounted) return;
            _loadForDesktop(availableWidth);
          });
        }

        if (!_loaded && itemsState.items.isEmpty && itemsState.error == null) {
          // Initial load (or server switched) – show loading instead of "empty" flash.
          final itemHeight = _itemWidth / 0.48;
          return SizedBox(
            height: itemHeight * _rowCount + _itemSpacing,
            child: const Center(child: CircularProgressIndicator()),
          );
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('加载失败', style: TextStyle(color: theme.colorScheme.error)),
                  const SizedBox(height: 8),
                  TextButton(onPressed: _retry, child: const Text('重试')),
                ],
              ),
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
            .floor()
            .clamp(1, 100);
        final itemWidth = (availableWidth - (itemsPerRow - 1) * _itemSpacing) / itemsPerRow;
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
                  key: ValueKey('poster_${item.type.name}_${item.id}'),
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
