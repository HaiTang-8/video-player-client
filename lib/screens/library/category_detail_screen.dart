import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/widgets/desktop_app_bar.dart';
import '../../core/widgets/loading_widget.dart';
import '../../core/widgets/mobile_app_bar.dart';
import '../../core/widgets/skeleton_loader.dart';
import '../../core/widgets/smooth_scroll_behavior.dart';
import '../../core/window/window_controls.dart';
import '../../data/models/models.dart';
import '../../providers/providers.dart';
import 'widgets/library_poster_card.dart';

/// 分类详情页面 - 展示该分类下所有影视
class CategoryDetailScreen extends ConsumerStatefulWidget {
  final String categoryId;
  final String categoryName;

  const CategoryDetailScreen({
    super.key,
    required this.categoryId,
    required this.categoryName,
  });

  @override
  ConsumerState<CategoryDetailScreen> createState() =>
      _CategoryDetailScreenState();
}

class _CategoryDetailScreenState extends ConsumerState<CategoryDetailScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      refreshCategoryItems(ref, widget.categoryId, pageSize: 30);
    });
  }

  bool _onScrollNotification(ScrollNotification notification) {
    if (notification is ScrollUpdateNotification) {
      if (notification.metrics.pixels >=
          notification.metrics.maxScrollExtent - 200) {
        loadMoreCategoryItems(ref, widget.categoryId, pageSize: 30);
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final itemsState = ref.watch(categoryItemsProvider(widget.categoryId));
    final isDesktop = WindowControls.isDesktop;

    return Scaffold(
      appBar: isDesktop
          ? DesktopAppBar(
              title: Text(widget.categoryName),
              onBack: () => context.pop(),
            )
          : MobileAppBar(
              title: Text(widget.categoryName),
              onBack: () => context.pop(),
            ),
      body: RefreshIndicator(
        onRefresh: () => refreshCategoryItems(ref, widget.categoryId, pageSize: 30),
        child: _buildBody(itemsState),
      ),
    );
  }

  Widget _buildBody(CategoryItemsState state) {
    if (state.isLoading && state.items.isEmpty) {
      return const GridSkeletonLoader();
    }

    if (state.error != null && state.items.isEmpty) {
      return AppErrorWidget(
        message: state.error!,
        onRetry: () => refreshCategoryItems(ref, widget.categoryId, pageSize: 30),
        scrollable: true,
      );
    }

    if (state.items.isEmpty) {
      return const EmptyWidget(
        message: '暂无内容',
        icon: Icons.movie_outlined,
        scrollable: true,
      );
    }

    final isDesktop = WindowControls.isDesktop;

    return DesktopSmoothScroll(
      child: NotificationListener<ScrollNotification>(
        onNotification: _onScrollNotification,
        child: GridView.builder(
          primary: true,
          clipBehavior: Clip.none,
          padding: EdgeInsets.all(isDesktop ? 24 : 16),
          gridDelegate: isDesktop
              ? const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 160.0,
                  childAspectRatio: 0.48,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                )
              : const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  childAspectRatio: 0.48,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
          itemCount: state.items.length + (state.isLoading ? 1 : 0),
          itemBuilder: (context, index) {
            if (index >= state.items.length) {
              return const Center(child: CircularProgressIndicator());
            }
            final item = state.items[index];
            return LibraryPosterCard(
              item: item,
              width: isDesktop ? 140.0 : double.infinity,
              onTap: () => _navigateToDetail(item),
            );
          },
        ),
      ),
    );
  }

  void _navigateToDetail(MediaItem item) {
    if (item.type == MediaType.movie) {
      context.push('/movie/${item.id}');
    } else {
      context.push('/tvshow/${item.id}');
    }
  }
}
