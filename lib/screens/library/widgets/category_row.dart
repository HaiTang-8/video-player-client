import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(categoryItemsProvider(widget.category.id).notifier).load();
    });
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _navigateToCategory(),
                  borderRadius: BorderRadius.circular(8),
                  splashColor: theme.colorScheme.primary.withValues(alpha: 0.2),
                  highlightColor: theme.colorScheme.primary.withValues(alpha: 0.1),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.category.displayName,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${widget.category.count}',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                        Icon(
                          Icons.chevron_right,
                          size: 20,
                          color: theme.colorScheme.primary,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // 水平滚动海报列表
        SizedBox(
          height: 280, // 增加高度以容纳标题
          child: itemsState.isLoading && itemsState.items.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : itemsState.error != null && itemsState.items.isEmpty
                  ? Center(
                      child: Text(
                        '加载失败',
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    )
                  : itemsState.items.isEmpty
                      ? Center(
                          child: Text(
                            '暂无内容',
                            style: TextStyle(color: theme.colorScheme.outline),
                          ),
                        )
                      : ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: itemsState.items.length,
                          itemBuilder: (context, index) {
                            final item = itemsState.items[index];
                            return Padding(
                              padding: const EdgeInsets.only(right: 16), // 增加间距
                              child: LibraryPosterCard(
                                item: item,
                                width: 140, // 增大卡片宽度
                                onTap: () => _navigateToDetail(item),
                              ),
                            );
                          },
                        ),
        ),

        const SizedBox(height: 8),
      ],
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
