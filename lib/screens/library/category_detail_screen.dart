import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/widgets/app_back_button.dart';
import '../../core/widgets/desktop_title_bar.dart';
import '../../core/widgets/loading_widget.dart';
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
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(categoryItemsProvider(widget.categoryId).notifier)
          .refresh(pageSize: 30);
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      ref
          .read(categoryItemsProvider(widget.categoryId).notifier)
          .loadMore(pageSize: 30);
    }
  }

  @override
  Widget build(BuildContext context) {
    final itemsState = ref.watch(categoryItemsProvider(widget.categoryId));
    final isDesktop = WindowControls.isDesktop;

    return Scaffold(
      appBar: isDesktop
          ? DesktopTitleBar(
              leading: AppBackButton(onPressed: () => context.pop()),
              title: Text(widget.categoryName),
              centerTitle: true,
            )
          : AppBar(
              leadingWidth: kAppBackButtonWidth,
              leading: AppBackButton(onPressed: () => context.pop()),
              title: Text(widget.categoryName),
            ),
      body: RefreshIndicator(
        onRefresh: () => ref
            .read(categoryItemsProvider(widget.categoryId).notifier)
            .refresh(pageSize: 30),
        child: _buildBody(itemsState),
      ),
    );
  }

  Widget _buildBody(CategoryItemsState state) {
    if (state.isLoading && state.items.isEmpty) {
      return const LoadingWidget(message: '加载中...');
    }

    if (state.error != null && state.items.isEmpty) {
      return AppErrorWidget(
        message: state.error!,
        onRetry: () => ref
            .read(categoryItemsProvider(widget.categoryId).notifier)
            .refresh(pageSize: 30),
      );
    }

    if (state.items.isEmpty) {
      return const EmptyWidget(
        message: '暂无内容',
        icon: Icons.movie_outlined,
      );
    }

    return GridView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 160,
        childAspectRatio: 0.55,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: state.items.length + (state.isLoading ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= state.items.length) {
          return const Center(child: CircularProgressIndicator());
        }
        final item = state.items[index];
        return LibraryPosterCard(
          item: item,
          width: 140,
          onTap: () => _navigateToDetail(item),
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
}
