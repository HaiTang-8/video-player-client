import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/window/window_controls.dart';
import '../../../data/models/models.dart';
import '../../../providers/providers.dart';
import 'media_poster_row.dart';

class CategoryRow extends ConsumerStatefulWidget {
  final CategoryStats category;

  const CategoryRow({required this.category, super.key});

  @override
  ConsumerState<CategoryRow> createState() => _CategoryRowState();
}

class _CategoryRowState extends ConsumerState<CategoryRow> {
  bool _loaded = false;
  String? _loadedServerUrl;

  @override
  void initState() {
    super.initState();
    if (!WindowControls.isDesktop) {
      _tryLoad();
    }
  }

  void _tryLoad({int? pageSize}) {
    final serverUrl = ref.read(serverUrlProvider);
    final service = ref.read(mediaServiceProvider);
    if (serverUrl == null || serverUrl.isEmpty || service == null) return;

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
    final itemWidth = MediaPosterRow.desktopItemWidth;
    final itemSpacing = MediaPosterRow.itemSpacing;
    final itemsPerRow = ((availableWidth + itemSpacing) /
            (itemWidth + itemSpacing))
        .floor()
        .clamp(1, 100);
    final pageSize = itemsPerRow * 2;
    _tryLoad(pageSize: pageSize);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(serverUrlProvider, (previous, next) {
      if (previous == next) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _loaded = false;
        _loadedServerUrl = null;
        if (WindowControls.isDesktop) {
          setState(() {});
        } else {
          _tryLoad();
        }
      });
    });

    final itemsState = ref.watch(categoryItemsProvider(widget.category.id));

    if (WindowControls.isDesktop && !_loaded) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final availableWidth =
              constraints.maxWidth - MediaPosterRow.horizontalPadding * 2;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _loadForDesktop(availableWidth);
          });
          return MediaPosterRow(
            title: widget.category.displayName,
            count: widget.category.count,
            onTitleTap: _navigateToCategory,
            isLoading: true,
            useDesktopGrid: true,
            onItemTap: _navigateToDetail,
          );
        },
      );
    }

    return MediaPosterRow(
      title: widget.category.displayName,
      count: widget.category.count,
      onTitleTap: _navigateToCategory,
      items: itemsState.items,
      isLoading: itemsState.isLoading,
      error: itemsState.error,
      onRetry: _retry,
      onItemTap: _navigateToDetail,
      itemKeyPrefix: 'poster',
      useDesktopGrid: WindowControls.isDesktop,
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
