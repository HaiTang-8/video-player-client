import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/widgets/loading_widget.dart';
import '../../core/window/window_controls.dart';
import '../../data/models/models.dart';
import '../../providers/providers.dart';
import '../library/widgets/library_poster_card.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _searchController = TextEditingController();
  Timer? _debounceTimer;

  int _selectedCategory = 0;
  int _selectedSort = 0;
  int _selectedType = 0;
  int _selectedRegion = 0;
  int _selectedYear = 0;

  static const _categories = ['全部', '电视剧', '电影', '动漫', '综艺', '演唱会', '纪录片'];
  static const _sorts = ['最新更新', '最新上映', '影片评分'];
  static const _types = ['类型', '剧情', '喜剧', '动作', '爱情', '惊悚', '犯罪', '悬疑', '战争', '科幻', '动画', '恐怖', '家庭', '冒险', '动作冒险', '奇幻', '历史', '音乐', '记录', '儿童', '真人秀', '脱口秀', '肥皂剧', '新闻', '西部'];
  static const _regions = ['地区', '中国大陆', '中国香港', '中国台湾', '新加坡', '欧美', '美国', '日本', '韩国', '泰国', '英国', '法国', '德国', '意大利', '西班牙', '印度', '俄罗斯', '加拿大', '澳大利亚', '爱尔兰', '瑞典', '巴西', '丹麦'];
  static const _years = ['年份', '2020年代', '2025', '2024', '2023', '2022', '2021', '2020', '2010年代', '2000年代', '90年代', '80年代', '70年代', '60年代', '更早'];

  @override
  void dispose() {
    _searchController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      ref.read(searchProvider.notifier).search(query);
    });
  }

  void _doSearch() {
    final query = _searchController.text.trim();
    if (query.isNotEmpty) {
      ref.read(searchProvider.notifier).search(query);
    }
  }

  @override
  Widget build(BuildContext context) {
    final searchState = ref.watch(searchProvider);

    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground,
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            _buildSearchBar(context),
            _buildFilterSection(),
            Expanded(child: _buildBody(searchState)),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    final leftInset = WindowControls.isMacOS ? 72.0 : 12.0;

    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 8,
        left: leftInset,
        right: 12,
        bottom: 8,
      ),
      color: CupertinoColors.systemGroupedBackground,
      child: Row(
        children: [
          CupertinoButton(
            padding: EdgeInsets.zero,
            minSize: 32,
            onPressed: () => context.pop(),
            child: const Icon(CupertinoIcons.back, size: 24),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: CupertinoSearchTextField(
              controller: _searchController,
              placeholder: '输入影片名称搜索',
              autofocus: true,
              onChanged: _onSearchChanged,
              onSubmitted: (_) => _doSearch(),
            ),
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _searchController,
            builder: (context, value, _) {
              final hasQuery = value.text.trim().isNotEmpty;
              final color =
                  hasQuery ? CupertinoColors.activeBlue : CupertinoColors.systemGrey;
              return CupertinoButton(
                padding: const EdgeInsets.only(left: 8),
                minSize: 32,
                onPressed: _doSearch,
                child: Text('搜索', style: TextStyle(fontSize: 15, color: color)),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFilterSection() {
    return Container(
      color: CupertinoColors.systemGroupedBackground,
      child: Column(
        children: [
          _buildFilterRow(_categories, _selectedCategory, (i) => setState(() => _selectedCategory = i)),
          _buildFilterRow(_sorts, _selectedSort, (i) => setState(() => _selectedSort = i)),
          _buildFilterRow(_types, _selectedType, (i) => setState(() => _selectedType = i)),
          _buildFilterRow(_regions, _selectedRegion, (i) => setState(() => _selectedRegion = i)),
          _buildFilterRow(_years, _selectedYear, (i) => setState(() => _selectedYear = i)),
        ],
      ),
    );
  }

  Widget _buildFilterRow(List<String> items, int selectedIndex, ValueChanged<int> onSelected) {
    return SizedBox(
      height: 32,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final selected = index == selectedIndex;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onSelected(index),
            child: Align(
              alignment: Alignment.center,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: selected
                    ? BoxDecoration(color: CupertinoColors.systemGrey5, borderRadius: BorderRadius.circular(11))
                    : null,
                child: Text(
                  items[index],
                  style: TextStyle(
                    color: selected ? CupertinoColors.activeBlue : CupertinoColors.black,
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    height: 1.0,
                    leadingDistribution: TextLeadingDistribution.even,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBody(SearchState state) {
    if (state.query.isEmpty) {
      return const EmptyWidget(message: '输入关键词搜索电影或剧集', icon: CupertinoIcons.search);
    }
    if (state.isLoading) {
      return const LoadingWidget(message: '搜索中...');
    }
    if (state.error != null) {
      return AppErrorWidget(
        message: state.error!,
        onRetry: () => ref.read(searchProvider.notifier).search(state.query),
      );
    }

    final allItems = _buildMediaItems(state);
    if (allItems.isEmpty) {
      return const EmptyWidget(message: '未找到相关内容', icon: CupertinoIcons.search);
    }

    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.52,
        crossAxisSpacing: 10,
        mainAxisSpacing: 12,
      ),
      itemCount: allItems.length,
      itemBuilder: (context, index) {
        final item = allItems[index];
        return LibraryPosterCard(
          item: item,
          width: double.infinity,
          onTap: () => _navigateToDetail(item),
        );
      },
    );
  }

  List<MediaItem> _buildMediaItems(SearchState state) {
    final List<MediaItem> items = [];
    final showMovies = _selectedCategory == 0 || _selectedCategory == 2;
    final showTvShows = _selectedCategory == 0 || _selectedCategory == 1;

    if (showMovies) {
      for (final movie in state.movies) {
        items.add(MediaItem(
          id: movie.id,
          title: movie.title,
          type: MediaType.movie,
          posterPath: movie.posterPath,
          rating: movie.rating,
          year: movie.year,
          releaseDate: movie.releaseDate,
        ));
      }
    }

    if (showTvShows) {
      for (final tv in state.tvShows) {
        items.add(MediaItem(
          id: tv.id,
          title: tv.name,
          type: MediaType.tvshow,
          posterPath: tv.posterPath,
          rating: tv.rating,
          year: tv.year,
          numberOfSeasons: tv.numberOfSeasons,
        ));
      }
    }

    if (_selectedSort == 2) {
      items.sort((a, b) => (b.rating ?? 0).compareTo(a.rating ?? 0));
    }

    return items;
  }

  void _navigateToDetail(MediaItem item) {
    if (item.type == MediaType.movie) {
      context.push('/movie/${item.id}');
    } else {
      context.push('/tvshow/${item.id}');
    }
  }
}
