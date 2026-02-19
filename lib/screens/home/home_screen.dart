import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' show LucideIcons;
import '../../core/widgets/poster_card.dart';
import '../../core/widgets/skeleton_loader.dart';
import '../../core/widgets/smooth_scroll_behavior.dart';
import '../../data/models/models.dart';
import '../../providers/providers.dart';

/// 首页/海报墙页面
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(postersProvider.notifier).loadPosters();
    });
  }

  bool _onScrollNotification(ScrollNotification notification) {
    if (notification is ScrollUpdateNotification) {
      if (notification.metrics.pixels >=
          notification.metrics.maxScrollExtent - 200) {
        ref.read(postersProvider.notifier).loadMore();
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final postersState = ref.watch(postersProvider);

    return Scaffold(
      body: DesktopSmoothScroll(
        child: NotificationListener<ScrollNotification>(
          onNotification: _onScrollNotification,
          child: RefreshIndicator(
            onRefresh: () => ref.read(postersProvider.notifier).refresh(),
            child: CustomScrollView(
              primary: true,
              slivers: [
            // AppBar
            SliverAppBar(
              floating: true,
              title: const Text('媒体库'),
              actions: [
                IconButton(
                  icon: const Icon(LucideIcons.search),
                  onPressed: () => context.push('/search'),
                ),
                IconButton(
                  icon: const Icon(LucideIcons.settings),
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

            if (postersState.isLoading && postersState.items.isEmpty)
              const SliverFillRemaining(
                child: GridSkeletonLoader(),
              ),
              ],
            ),
          ),
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
