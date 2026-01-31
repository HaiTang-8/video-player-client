import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/widgets/desktop_title_bar.dart';
import '../../core/widgets/smooth_scroll_behavior.dart';
import '../../core/window/window_controls.dart';
import '../../core/widgets/skeleton_loader.dart';
import '../../providers/providers.dart';
import 'widgets/category_row.dart';
import 'widgets/local_media_row.dart';
import 'widgets/watch_history_row.dart';

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
      if (!mounted) return;
      ref.read(categoriesProvider.notifier).load();
      ref.read(watchHistoryProvider.notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(serverUrlProvider, (previous, next) {
      if (previous != next && next != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ref.read(categoriesProvider.notifier).load();
          ref.read(watchHistoryProvider.notifier).load();
        });
      }
    });

    final categoriesState = ref.watch(categoriesProvider);
    final isDesktop = WindowControls.isDesktop;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? null : const Color(0xFFF2F2F7),
      appBar: isDesktop
          ? DesktopTitleBar(
              title: const Text('媒体库'),
              centerTitle: true,
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
            )
          : AppBar(
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
      body: DesktopSmoothScroll(
        child: RefreshIndicator(
          onRefresh: () async {
            await Future.wait([
              ref.read(categoriesProvider.notifier).refresh(),
              ref.read(watchHistoryProvider.notifier).refresh(),
            ]);
          },
          child: _buildBody(categoriesState),
        ),
      ),
    );
  }

  Widget _buildBody(CategoriesState state) {
    if (state.isLoading && state.categories.isEmpty) {
      return const LibrarySkeletonLoader();
    }

    if (state.error != null && state.categories.isEmpty) {
      return AppErrorWidget(
        message: state.error!,
        onRetry: () => ref.read(categoriesProvider.notifier).load(),
        scrollable: true,
      );
    }

    // 过滤掉空分类和 recent 分类（最近观看由 WatchHistoryRow 单独处理）
    final nonEmptyCategories = state.categories
        .where((c) => c.count > 0 && c.id != 'recent')
        .toList();

    final watchHistoryState = ref.watch(watchHistoryProvider);
    final hasWatchHistory = watchHistoryState.items.isNotEmpty;

    final downloadState = ref.watch(downloadManagerProvider);
    final hasLocalMedia = downloadState.completedTasks.isNotEmpty;

    if (nonEmptyCategories.isEmpty && !hasWatchHistory && !hasLocalMedia) {
      return const EmptyWidget(
        message: '暂无媒体内容\n请先添加存储源并扫描',
        icon: Icons.movie_outlined,
        scrollable: true,
      );
    }

    // 计算特殊行数量：最近观看 + 本地影片
    int specialRowCount = 0;
    if (hasWatchHistory) specialRowCount++;
    if (hasLocalMedia) specialRowCount++;

    return ListView.builder(
      primary: true,
      padding: const EdgeInsets.only(top: 8, bottom: 16),
      itemCount: nonEmptyCategories.length + specialRowCount,
      itemBuilder: (context, index) {
        // 第一项显示最近观看
        if (hasWatchHistory && index == 0) {
          return const WatchHistoryRow();
        }
        // 第二项（或第一项如果没有观看历史）显示本地影片
        final localMediaIndex = hasWatchHistory ? 1 : 0;
        if (hasLocalMedia && index == localMediaIndex) {
          return const LocalMediaRow();
        }
        final categoryIndex = index - specialRowCount;
        return CategoryRow(
          key: ValueKey('category_${nonEmptyCategories[categoryIndex].id}'),
          category: nonEmptyCategories[categoryIndex],
        );
      },
    );
  }
}
