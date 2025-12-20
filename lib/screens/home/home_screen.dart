import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/widgets/poster_card.dart';
import '../../core/widgets/loading_widget.dart';
import '../../data/models/models.dart';
import '../../providers/providers.dart';

/// 首页/海报墙页面
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    // 加载数据
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(postersProvider.notifier).loadPosters();
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
      ref.read(postersProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final postersState = ref.watch(postersProvider);

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => ref.read(postersProvider.notifier).refresh(),
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            // AppBar
            SliverAppBar(
              floating: true,
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

            // 内容
            if (postersState.error != null && postersState.items.isEmpty)
              SliverFillRemaining(
                child: AppErrorWidget(
                  message: postersState.error!,
                  onRetry: () => ref.read(postersProvider.notifier).loadPosters(),
                ),
              )
            else if (postersState.items.isEmpty && !postersState.isLoading)
              const SliverFillRemaining(
                child: EmptyWidget(
                  message: '暂无媒体内容\n请先添加存储源并扫描',
                  icon: Icons.movie_outlined,
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 180,
                    childAspectRatio: 0.65,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      if (index >= postersState.items.length) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: CircularProgressIndicator(),
                          ),
                        );
                      }

                      final item = postersState.items[index];
                      return PosterCard(
                        item: item,
                        onTap: () => _navigateToDetail(item),
                      );
                    },
                    childCount: postersState.items.length +
                        (postersState.isLoading && postersState.items.isNotEmpty
                            ? 1
                            : 0),
                  ),
                ),
              ),

            // 初始加载
            if (postersState.isLoading && postersState.items.isEmpty)
              const SliverFillRemaining(
                child: LoadingWidget(message: '加载中...'),
              ),
          ],
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
