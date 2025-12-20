import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/widgets/loading_widget.dart';
import '../../providers/providers.dart';
import 'widgets/category_row.dart';

/// 媒体库页面 - 分类横向滚动展示
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(categoriesProvider.notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final categoriesState = ref.watch(categoriesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('媒体库'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => context.push('/search'),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(categoriesProvider.notifier).refresh(),
        child: _buildBody(categoriesState),
      ),
    );
  }

  Widget _buildBody(CategoriesState state) {
    if (state.isLoading && state.categories.isEmpty) {
      return const LoadingWidget(message: '加载中...');
    }

    if (state.error != null && state.categories.isEmpty) {
      return AppErrorWidget(
        message: state.error!,
        onRetry: () => ref.read(categoriesProvider.notifier).load(),
      );
    }

    // 过滤掉空分类
    final nonEmptyCategories =
        state.categories.where((c) => c.count > 0).toList();

    if (nonEmptyCategories.isEmpty) {
      return const EmptyWidget(
        message: '暂无媒体内容\n请先添加存储源并扫描',
        icon: Icons.movie_outlined,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 16),
      itemCount: nonEmptyCategories.length,
      itemBuilder: (context, index) {
        return CategoryRow(category: nonEmptyCategories[index]);
      },
    );
  }
}
