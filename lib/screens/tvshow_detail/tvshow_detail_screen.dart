import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pull_down_button/pull_down_button.dart';
import '../../core/widgets/app_back_button.dart';
import '../../core/widgets/scrollable_row_with_arrows.dart';
import '../../core/widgets/cast_avatar.dart';
import '../../core/widgets/desktop_app_bar.dart';
import '../../core/widgets/image_selector_sheet.dart';
import '../../core/widgets/dialog_utils.dart';
import '../../core/window/window_controls.dart';
import '../../core/widgets/skeleton_loader.dart';
import '../../core/widgets/overview_preview_text.dart';
import '../../core/utils/image_proxy.dart';
import '../../data/models/models.dart';
import '../../data/services/api_client.dart';
import '../../providers/providers.dart';

/// Emby 风格剧集详情页面
class TvShowDetailScreen extends ConsumerStatefulWidget {
  final int tvShowId;

  const TvShowDetailScreen({super.key, required this.tvShowId});

  @override
  ConsumerState<TvShowDetailScreen> createState() => _TvShowDetailScreenState();
}

class _TvShowDetailScreenState extends ConsumerState<TvShowDetailScreen> {
  int? _selectedSeasonId;
  int _selectedSeasonIndex = 0;
  final _castScrollController = ScrollController();
  final _crewScrollController = ScrollController();
  final _episodesScrollController = ScrollController();
  WatchHistoryItem? _watchHistory;

  @override
  void initState() {
    super.initState();
    _loadWatchHistory();
  }

  Future<void> _loadWatchHistory() async {
    final service = ref.read(mediaServiceProvider);
    if (service == null) return;
    final resp = await service.getWatchProgress('tv', widget.tvShowId);
    if (!mounted) return;
    if (resp.isSuccess && resp.data != null && !resp.data!.completed) {
      setState(() => _watchHistory = resp.data);
    } else {
      setState(() => _watchHistory = null);
    }
  }

  @override
  void dispose() {
    _castScrollController.dispose();
    _crewScrollController.dispose();
    _episodesScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tvShowAsync = ref.watch(tvShowDetailProvider(widget.tvShowId));
    final theme = Theme.of(context);
    final screenSize = MediaQuery.of(context).size;
    final isDesktop = WindowControls.isDesktop;
    final serverBaseUrl = ref.watch(serverUrlProvider);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar:
          isDesktop
              ? tvShowAsync.when(
                loading:
                    () => DesktopAppBar(
                      title: const Text('加载中...'),
                      onBack: () => context.pop(),
                    ),
                error:
                    (error, stack) => DesktopAppBar(
                      title: const Text('剧集详情'),
                      onBack: () => context.pop(),
                      actions: [
                        IconButton(
                          icon: const Icon(Icons.refresh),
                          onPressed:
                              () => ref.invalidate(
                                tvShowDetailProvider(widget.tvShowId),
                              ),
                        ),
                      ],
                    ),
                data:
                    (tvShow) => DesktopAppBar(
                      title: Text(tvShow?.name ?? '剧集详情'),
                      onBack: () => context.pop(),
                      actions: _buildDesktopActions(tvShow),
                    ),
              )
              : null,
      body: tvShowAsync.when(
        loading: () => const DetailSkeletonLoader(),
        error:
            (error, stack) => AppErrorWidget(
              message: error.toString(),
              onRetry:
                  () => ref.invalidate(tvShowDetailProvider(widget.tvShowId)),
            ),
        data: (tvShow) {
          if (tvShow == null) {
            return const AppErrorWidget(message: '剧集不存在');
          }

          final cast =
              (tvShow.castDetail != null && tvShow.castDetail!.isNotEmpty)
                  ? tvShow.castDetail!
                  : (tvShow.cast != null
                      ? tvShow.cast!
                          .where((e) => e.trim().isNotEmpty)
                          .map((e) => CastMember(name: e.trim()))
                          .toList()
                      : const <CastMember>[]);

          // 默认选中第一季
          if (_selectedSeasonId == null &&
              tvShow.seasons != null &&
              tvShow.seasons!.isNotEmpty) {
            _selectedSeasonId = tvShow.seasons!.first.id;
            _selectedSeasonIndex = 0;
          }

          final selectedSeason =
              tvShow.seasons != null &&
                      _selectedSeasonIndex < tvShow.seasons!.length
                  ? tvShow.seasons![_selectedSeasonIndex]
                  : null;

          final seasonBackdrop =
              tvShow.backdrops != null && tvShow.backdrops!.isNotEmpty
                  ? tvShow.backdrops![_selectedSeasonIndex %
                      tvShow.backdrops!.length]
                  : null;
          final episodeFallbackImage =
              seasonBackdrop ??
              selectedSeason?.posterPath ??
              tvShow.backdropPath ??
              tvShow.posterPath;

          return CustomScrollView(
            slivers: [
              // 顶部导航栏
              if (!isDesktop) _buildAppBar(context, tvShow, selectedSeason),

              // 背景图区域（含渐变蒙版和 Hero 内容）
              SliverToBoxAdapter(
                child: _buildBackgroundWithHero(
                  context,
                  tvShow,
                  selectedSeason,
                  screenSize,
                  serverBaseUrl,
                  isDesktop: isDesktop,
                ),
              ),

              // 剧集选择区
              if (tvShow.seasons != null && tvShow.seasons!.isNotEmpty)
                SliverToBoxAdapter(
                  child: _buildEpisodeSelector(context, theme, tvShow),
                ),

              // 剧集卡片列表
              if (selectedSeason != null &&
                  selectedSeason.episodes != null &&
                  selectedSeason.episodes!.isNotEmpty)
                SliverToBoxAdapter(
                  child: _EpisodesCarouselDirect(
                    episodes: selectedSeason.episodes!,
                    tvShowId: widget.tvShowId,
                    seasonId: selectedSeason.id,
                    tvShowName: tvShow.name,
                    serverBaseUrl: serverBaseUrl,
                    fallbackImageUrl: episodeFallbackImage,
                    scrollController: _episodesScrollController,
                  ),
                )
              else if (_selectedSeasonId != null)
                SliverToBoxAdapter(
                  child: _EpisodesCarousel(
                    tvShowId: widget.tvShowId,
                    seasonId: _selectedSeasonId!,
                    tvShowName: tvShow.name,
                    fallbackImageUrl: episodeFallbackImage,
                    scrollController: _episodesScrollController,
                  ),
                ),

              // 剧情简介
              if (!isDesktop &&
                  tvShow.overview != null &&
                  tvShow.overview!.isNotEmpty)
                SliverToBoxAdapter(child: _buildOverviewSection(tvShow)),

              // 相关演员区
              if ((selectedSeason?.castDetail != null &&
                      selectedSeason!.castDetail!.isNotEmpty) ||
                  (selectedSeason?.crewDetail != null &&
                      selectedSeason!.crewDetail!.isNotEmpty))
                SliverToBoxAdapter(
                  child: _buildSeasonCreditsSection(
                    context,
                    theme,
                    selectedSeason,
                    serverBaseUrl,
                  ),
                )
              else if (cast.isNotEmpty)
                SliverToBoxAdapter(
                  child: _buildCastSection(context, theme, cast, serverBaseUrl),
                ),

              // 文件信息区
              SliverToBoxAdapter(
                child: _buildFileInfoSection(context, theme, tvShow),
              ),

              // 底部间距
              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ],
          );
        },
      ),
    );
  }

  /// 构建背景图（含渐变蒙版和 Hero 内容）
  Widget _buildBackgroundWithHero(
    BuildContext context,
    TvShow tvShow,
    Season? selectedSeason,
    Size screenSize,
    String? serverBaseUrl, {
    required bool isDesktop,
  }) {
    String? imagePathRaw;
    bool usePoster = false;
    if (isDesktop) {
      // 优先使用 backdropPath（用户可能手动选择过）
      imagePathRaw = tvShow.backdropPath;
      // 如果 backdropPath 为空，再从 backdrops 列表中取
      if ((imagePathRaw == null || imagePathRaw.isEmpty) &&
          tvShow.backdrops != null &&
          tvShow.backdrops!.isNotEmpty) {
        imagePathRaw = tvShow.backdrops![_selectedSeasonIndex % tvShow.backdrops!.length];
      }
      if (imagePathRaw == null || imagePathRaw.isEmpty) {
        imagePathRaw = selectedSeason?.posterPath ?? tvShow.posterPath;
        usePoster = true;
      }
    } else {
      imagePathRaw = selectedSeason?.posterPath ?? tvShow.posterPath;
      usePoster = true;
      if (imagePathRaw == null || imagePathRaw.isEmpty) {
        imagePathRaw = tvShow.backdropPath;
        usePoster = false;
      }
    }

    String? imagePath = imagePathRaw;
    if (imagePathRaw != null && ImageProxy.isTMDBImageUrl(imagePathRaw)) {
      final uri = Uri.tryParse(imagePathRaw);
      final segments = uri?.pathSegments ?? const <String>[];
      final currentSize = segments.length >= 3 ? segments[2] : '';
      const smallSizes = <String>{'w92', 'w154', 'w185', 'w342', 'w500'};
      if (smallSizes.contains(currentSize)) {
        imagePath = ImageProxy.withTMDBSize(
          imagePathRaw,
          usePoster ? 'w780' : 'w1280',
        );
      }
    }

    final imageHeight =
        (() {
          if (usePoster) {
            return screenSize.height * 0.7;
          }
          const backdropAspect = 16 / 9;
          final idealHeight = screenSize.width / backdropAspect;
          final minHeight = screenSize.height * 0.55;
          final maxHeight = screenSize.height * 0.9;
          return idealHeight.clamp(minHeight, maxHeight);
        })().ceilToDouble();

    final gradientHeight = (imageHeight * 0.5).ceilToDouble();
    final imageUrl =
        imagePath != null && imagePath.isNotEmpty
            ? ImageProxy.proxyTMDBIfNeeded(imagePath, serverBaseUrl)
            : null;

    return Stack(
      children: [
        // 背景图
        if (imageUrl != null && imageUrl.isNotEmpty)
          CachedNetworkImage(
            imageUrl: imageUrl,
            width: double.infinity,
            height: imageHeight,
            fit: BoxFit.fill,
            alignment: Alignment.center,
            errorWidget:
                (_, __, ___) =>
                    Container(height: imageHeight, color: Colors.grey[300]),
            placeholder:
                (_, __) =>
                    Container(height: imageHeight, color: Colors.grey[300]),
          )
        else
          Container(height: imageHeight, color: Colors.grey[300]),

        // 渐变蒙版
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: gradientHeight,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white.withValues(alpha: 0.0),
                  Colors.white.withValues(alpha: 0.2),
                  Colors.white.withValues(alpha: 0.5),
                  Colors.white.withValues(alpha: 0.8),
                  Colors.white,
                ],
                stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
              ),
            ),
          ),
        ),

        // Hero 内容（叠加在渐变蒙版上）
        Positioned(
          left: 12,
          right: 12,
          bottom: 24,
          child:
              isDesktop
                  ? _buildDesktopHeroContent(context, tvShow, selectedSeason)
                  : _buildMobileHeroContent(context, tvShow, selectedSeason),
        ),
      ],
    );
  }

  Widget _buildDesktopHeroContent(
    BuildContext context,
    TvShow tvShow,
    Season? selectedSeason,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          (tvShow.seasons != null &&
                  tvShow.seasons!.length > 1 &&
                  selectedSeason != null)
              ? '${tvShow.name} ${selectedSeason.displayName}'
              : tvShow.name,
          style: const TextStyle(
            color: Colors.black,
            fontSize: 28,
            fontWeight: FontWeight.bold,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildPlayButton(context),
            const SizedBox(width: 24),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildMetadataRow(tvShow, selectedSeason, forOverlay: false),
                  if (selectedSeason?.overview != null &&
                      selectedSeason!.overview!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      selectedSeason.overview!,
                      style: TextStyle(
                        color: Colors.black.withValues(alpha: 0.8),
                        fontSize: 14,
                        height: 1.5,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ] else if (tvShow.overview != null &&
                      tvShow.overview!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      tvShow.overview!,
                      style: TextStyle(
                        color: Colors.black.withValues(alpha: 0.8),
                        fontSize: 14,
                        height: 1.5,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMobileHeroContent(
    BuildContext context,
    TvShow tvShow,
    Season? selectedSeason,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 第一行：标题
        Text(
          (tvShow.seasons != null &&
                  tvShow.seasons!.length > 1 &&
                  selectedSeason != null)
              ? '${tvShow.name} ${selectedSeason.displayName}'
              : tvShow.name,
          style: const TextStyle(
            color: Colors.black,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        // 第二行：元数据
        _buildMetadataRow(tvShow, selectedSeason, forOverlay: false),
        const SizedBox(height: 12),
        // 第三行：全宽播放按钮
        _buildFullWidthPlayButton(context),
      ],
    );
  }

  Widget _buildFullWidthPlayButton(BuildContext context) {
    final history = _watchHistory;
    String buttonText = '播放';
    if (history != null && history.mediaInfo?.episodeInfo != null) {
      final ep = history.mediaInfo!.episodeInfo!;
      final pos = history.position;
      final m = (pos ~/ 60).toString().padLeft(2, '0');
      final s = (pos % 60).toString().padLeft(2, '0');
      buttonText = '第${ep.seasonNumber}季 第${ep.episodeNumber}集 $m:$s';
    }
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: Colors.black,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: () => _playFromHistory(context),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.play_arrow, color: Colors.white, size: 24),
                const SizedBox(width: 8),
                Text(
                  buttonText,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOverviewSection(TvShow tvShow) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '剧情简介',
            style: TextStyle(
              color: Colors.black,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          OverviewPreviewText(
            title: tvShow.name,
            overview: tvShow.overview!,
            maxLines: 3,
            style: TextStyle(
              color: Colors.black.withValues(alpha: 0.7),
              fontSize: 13,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  /// 构建顶部导航栏
  Widget _buildAppBar(BuildContext context, TvShow tvShow, Season? selectedSeason) {
    final hasDownloadableEpisodes = selectedSeason != null &&
        selectedSeason.episodes != null &&
        selectedSeason.episodes!.any((e) => e.hasFile);

    return SliverAppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      pinned: true,
      toolbarHeight: 44,
      centerTitle: true,
      automaticallyImplyLeading: false,
      leadingWidth: kAppBackButtonWidth,
      leading: AppBackButton(
        onPressed: () => context.pop(),
        color: Colors.black,
      ),
      title: Text(tvShow.name),
      actions: [
        if (hasDownloadableEpisodes)
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            onPressed: () => _navigateToDownload(context, tvShow, selectedSeason),
            child: const Icon(CupertinoIcons.cloud_download, color: Colors.black, size: 22),
          ),
        PullDownButton(
          itemBuilder: (context) => [
            PullDownMenuItem(
              title: '更换海报',
              icon: CupertinoIcons.photo,
              onTap: () => _showImageSelector(context, tvShow, ImageSelectorType.poster, selectedSeason: selectedSeason),
            ),
            PullDownMenuItem(
              title: '重新刮削',
              icon: CupertinoIcons.wand_stars,
              onTap: () => _scrapeTvShow(context, widget.tvShowId),
            ),
            PullDownMenuItem(
              title: '同步季度',
              icon: CupertinoIcons.arrow_2_circlepath,
              onTap: () => _syncTvShowSeasons(context, widget.tvShowId, tvShow.tmdbId),
            ),
            PullDownMenuItem(
              title: '刷新',
              icon: CupertinoIcons.refresh,
              onTap: () => ref.invalidate(tvShowDetailProvider(widget.tvShowId)),
            ),
          ],
          buttonBuilder: (context, showMenu) => CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            onPressed: showMenu,
            child: const Icon(CupertinoIcons.ellipsis, color: Colors.black, size: 22),
          ),
        ),
      ],
    );
  }

  void _navigateToDownload(BuildContext context, TvShow tvShow, Season season) {
    context.push('/download-episodes', extra: {
      'tvShowName': tvShow.name,
      'seasonNumber': season.seasonNumber,
      'season': season,
      'storageName': tvShow.storageName,
    });
  }

  List<Widget> _buildDesktopActions(TvShow? tvShow) {
    if (tvShow == null) return [];

    final selectedSeason =
        tvShow.seasons != null && _selectedSeasonIndex < tvShow.seasons!.length
            ? tvShow.seasons![_selectedSeasonIndex]
            : null;
    final hasDownloadableEpisodes = selectedSeason != null &&
        selectedSeason.episodes != null &&
        selectedSeason.episodes!.any((e) => e.hasFile);

    return [
      if (hasDownloadableEpisodes)
        IconButton(
          tooltip: '下载',
          icon: const Icon(CupertinoIcons.cloud_download),
          onPressed: () => _navigateToDownload(context, tvShow, selectedSeason),
        ),
      PullDownButton(
        itemBuilder: (context) => [
          PullDownMenuItem(
            title: '更换海报',
            icon: CupertinoIcons.photo,
            onTap: () => _showImageSelector(context, tvShow, ImageSelectorType.poster),
          ),
          PullDownMenuItem(
            title: '更换背景图',
            icon: CupertinoIcons.photo_on_rectangle,
            onTap: () => _showImageSelector(context, tvShow, ImageSelectorType.backdrop),
          ),
          PullDownMenuItem(
            title: '重新刮削',
            icon: CupertinoIcons.wand_stars,
            onTap: () => _scrapeTvShow(context, widget.tvShowId),
          ),
          PullDownMenuItem(
            title: '同步季度',
            icon: CupertinoIcons.arrow_2_circlepath,
            onTap: () => _syncTvShowSeasons(context, widget.tvShowId, tvShow.tmdbId),
          ),
          PullDownMenuItem(
            title: '刷新',
            icon: CupertinoIcons.refresh,
            onTap: () => ref.invalidate(tvShowDetailProvider(widget.tvShowId)),
          ),
        ],
        buttonBuilder: (context, showMenu) => IconButton(
          tooltip: '更多',
          icon: const Icon(CupertinoIcons.ellipsis),
          onPressed: showMenu,
        ),
      ),
    ];
  }

  /// 构建播放按钮
  Widget _buildPlayButton(BuildContext context) {
    final history = _watchHistory;
    String buttonText = '播放';
    if (history != null && history.mediaInfo?.episodeInfo != null) {
      final ep = history.mediaInfo!.episodeInfo!;
      final pos = history.position;
      final m = (pos ~/ 60).toString().padLeft(2, '0');
      final s = (pos % 60).toString().padLeft(2, '0');
      buttonText = '第${ep.seasonNumber}季 第${ep.episodeNumber}集 $m:$s';
    }
    return Material(
      color: Colors.black,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: () => _playFromHistory(context),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: WindowControls.isDesktop ? 48 : 32,
            vertical: 14,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.play_arrow, color: Colors.white, size: 24),
              const SizedBox(width: 8),
              Text(
                buttonText,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _playFromHistory(BuildContext context) async {
    final history = _watchHistory;
    if (history != null && history.episodeId != null && history.mediaInfo?.episodeInfo != null) {
      final ep = history.mediaInfo!.episodeInfo!;
      await context.push(
        '/player/episode/${widget.tvShowId}/${ep.seasonId}/${history.episodeId}',
        extra: {'position': history.position},
      );
      if (!mounted) return;
      await _loadWatchHistory();
      ref.read(watchHistoryProvider.notifier).refresh();
    }
    // TODO: 无历史时播放第一集
  }

  /// 构建元数据行
  Widget _buildMetadataRow(
    TvShow tvShow,
    Season? selectedSeason, {
    bool forOverlay = false,
  }) {
    final items = <Widget>[];

    // 评分
    if (tvShow.rating != null && tvShow.rating! > 0) {
      items.add(
        _buildMetadataItem(
          '豆 ${tvShow.rating!.toStringAsFixed(1)}',
          Colors.green,
          forOverlay: forOverlay,
        ),
      );
    }

    // 首播日期
    if (tvShow.firstAirDate != null) {
      items.add(
        _buildMetadataItem(
          '${tvShow.firstAirDate!.year}-${tvShow.firstAirDate!.month.toString().padLeft(2, '0')}-${tvShow.firstAirDate!.day.toString().padLeft(2, '0')}',
          null,
          forOverlay: forOverlay,
        ),
      );
    } else if (tvShow.year != null) {
      items.add(
        _buildMetadataItem('${tvShow.year}', null, forOverlay: forOverlay),
      );
    }

    // 剧集数
    if (selectedSeason?.episodeCount != null) {
      items.add(
        _buildMetadataItem(
          '共${selectedSeason!.episodeCount}集',
          null,
          forOverlay: forOverlay,
        ),
      );
    } else if (tvShow.numberOfEpisodes != null) {
      items.add(
        _buildMetadataItem(
          '共${tvShow.numberOfEpisodes}集',
          null,
          forOverlay: forOverlay,
        ),
      );
    }

    // 状态
    if (tvShow.status != null) {
      items.add(
        _buildMetadataItem(tvShow.statusText, null, forOverlay: forOverlay),
      );
    }

    return Wrap(spacing: 16, runSpacing: 8, children: items);
  }

  Widget _buildMetadataItem(
    String text,
    Color? color, {
    bool forOverlay = false,
  }) {
    final defaultColor =
        forOverlay
            ? Colors.white.withValues(alpha: 0.85)
            : Colors.black.withValues(alpha: 0.7);
    return Text(
      text,
      style: TextStyle(
        color: color ?? defaultColor,
        fontSize: 14,
        fontWeight: color != null ? FontWeight.bold : FontWeight.normal,
        shadows:
            forOverlay
                ? const [
                  Shadow(
                    offset: Offset(0, 1),
                    blurRadius: 2,
                    color: Colors.black45,
                  ),
                ]
                : null,
      ),
    );
  }

  /// 构建剧集选择区 - 季度标签页
  Widget _buildEpisodeSelector(
    BuildContext context,
    ThemeData theme,
    TvShow tvShow,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 分季切换标签 + 箭头按钮
          SizedBox(
            height: 44,
            child: Row(
              children: [
                Expanded(
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: tvShow.seasons!.length,
                    itemBuilder: (context, index) {
                      final season = tvShow.seasons![index];
                      final isSelected = index == _selectedSeasonIndex;

                      return Padding(
                        padding: const EdgeInsets.only(right: 32.0),
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedSeasonIndex = index;
                              _selectedSeasonId = season.id;
                            });
                          },
                          child: IntrinsicWidth(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // 文本 + 播放源数量角标 + 下拉箭头
                                _SeasonTabLabel(
                                  tvShowId: widget.tvShowId,
                                  season: season,
                                  isSelected: isSelected,
                                  isSingleSeason: tvShow.seasons!.length == 1,
                                ),
                                const SizedBox(height: 4),
                                // 指示器
                                Container(
                                  height: 3.0,
                                  decoration: BoxDecoration(
                                    color:
                                        isSelected
                                            ? Colors.black
                                            : Colors.transparent,
                                    borderRadius: BorderRadius.circular(1.5),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                if (WindowControls.isDesktop)
                  _EpisodesScrollButtons(
                    key: ValueKey(_selectedSeasonId),
                    controller: _episodesScrollController,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  /// 构建相关演员区
  Widget _buildCastSection(
    BuildContext context,
    ThemeData theme,
    List<CastMember> cast,
    String? serverBaseUrl, {
    String title = '相关演员',
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: ScrollableRowWithArrows(
        controller: _castScrollController,
        itemWidth: 80,
        itemSpacing: 8,
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.black,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        child: SizedBox(
          height: 120,
          child: ListView.separated(
            controller: _castScrollController,
            physics: ScrollableRowWithArrows.disableManualScroll
                ? const NeverScrollableScrollPhysics()
                : null,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            scrollDirection: Axis.horizontal,
            itemCount: cast.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              return _buildCastCard(cast[index], serverBaseUrl);
            },
          ),
        ),
      ),
    );
  }

  Widget _buildSeasonCreditsSection(
    BuildContext context,
    ThemeData theme,
    Season season,
    String? serverBaseUrl,
  ) {
    final cast = season.castDetail ?? const <CastMember>[];
    final crew = season.crewDetail ?? const <CrewMember>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (crew.isNotEmpty)
          _buildCrewSection(
            context,
            theme,
            crew,
            serverBaseUrl,
            title: '${season.displayName} 职员',
          ),
        if (cast.isNotEmpty)
          _buildCastSection(
            context,
            theme,
            cast,
            serverBaseUrl,
            title: '${season.displayName} 演员',
          ),
      ],
    );
  }

  Widget _buildCrewSection(
    BuildContext context,
    ThemeData theme,
    List<CrewMember> crew,
    String? serverBaseUrl, {
    String title = '职员',
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: ScrollableRowWithArrows(
        controller: _crewScrollController,
        itemWidth: 80,
        itemSpacing: 8,
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.black,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        child: SizedBox(
          height: 120,
          child: ListView.separated(
            controller: _crewScrollController,
            physics: ScrollableRowWithArrows.disableManualScroll
                ? const NeverScrollableScrollPhysics()
                : null,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            scrollDirection: Axis.horizontal,
            itemCount: crew.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              return _buildCrewCard(crew[index], serverBaseUrl);
            },
          ),
        ),
      ),
    );
  }

  Widget _buildCrewCard(CrewMember member, String? serverBaseUrl) {
    final name = member.name;
    final job =
        (member.job?.trim().isNotEmpty ?? false) ? member.job!.trim() : null;
    final dept =
        (member.department?.trim().isNotEmpty ?? false)
            ? member.department!.trim()
            : null;
    final role = job ?? dept;
    final profileUrl = member.profilePath;

    return SizedBox(
      width: 80,
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black.withValues(alpha: 0.1),
              border: Border.all(
                color: Colors.black.withValues(alpha: 0.2),
                width: 2,
              ),
            ),
            child: ClipOval(
              child: CastAvatar(
                size: 64,
                imageUrl: profileUrl,
                serverBaseUrl: serverBaseUrl,
                iconColor: Colors.black.withValues(alpha: 0.5),
                iconSize: 32,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            name,
            style: const TextStyle(
              color: Colors.black,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          if (role != null && role.isNotEmpty)
            Text(
              role,
              style: TextStyle(
                color: Colors.black.withValues(alpha: 0.5),
                fontSize: 10,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
        ],
      ),
    );
  }

  /// 构建演员卡片
  Widget _buildCastCard(CastMember member, String? serverBaseUrl) {
    final name = member.name;
    final role = member.character;
    final profileUrl = member.profilePath;

    return SizedBox(
      width: 80,
      child: Column(
        children: [
          // 圆形头像
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black.withValues(alpha: 0.1),
              border: Border.all(
                color: Colors.black.withValues(alpha: 0.2),
                width: 2,
              ),
            ),
            child: ClipOval(
              child: CastAvatar(
                size: 64,
                imageUrl: profileUrl,
                serverBaseUrl: serverBaseUrl,
                iconColor: Colors.black.withValues(alpha: 0.5),
                iconSize: 32,
              ),
            ),
          ),
          const SizedBox(height: 8),

          // 姓名
          Text(
            name,
            style: const TextStyle(
              color: Colors.black,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),

          // 角色信息（TMDB credits 可提供 character；其它来源可能为空）
          if (role != null && role.isNotEmpty)
            Text(
              '饰 $role',
              style: TextStyle(
                color: Colors.black.withValues(alpha: 0.5),
                fontSize: 10,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
        ],
      ),
    );
  }

  Future<void> _showImageSelector(
    BuildContext context,
    TvShow tvShow,
    ImageSelectorType type, {
    Season? selectedSeason,
  }) async {
    final service = ref.read(mediaServiceProvider);
    final serverBaseUrl = ref.read(serverUrlProvider);
    final isDesktop = WindowControls.isDesktop;
    if (service == null) {
      DialogUtils.showToast(context: context, message: '未连接到服务器', isError: true);
      return;
    }

    if (tvShow.tmdbId == null) {
      DialogUtils.showToast(context: context, message: '无 TMDB ID，无法获取图片', isError: true);
      return;
    }

    DialogUtils.showLoadingDialog(context: context, message: '加载图片中...');

    final resp = await service.getTvShowImages(tvShow.id);

    if (context.mounted) {
      Navigator.pop(context);
    }
    if (!context.mounted) return;

    if (!resp.isSuccess || resp.data == null) {
      DialogUtils.showToast(
        context: context,
        message: resp.error ?? '获取图片失败',
        isError: true,
      );
      return;
    }

    final images = type == ImageSelectorType.poster
        ? resp.data!.posters
        : resp.data!.backdrops;

    // 移动端海报使用季度海报，PC端使用剧集主海报/背景图
    final currentUrl = type == ImageSelectorType.poster
        ? (isDesktop ? tvShow.posterPath : (selectedSeason?.posterPath ?? tvShow.posterPath))
        : tvShow.backdropPath;

    showImageSelector(
      context: context,
      images: images,
      type: type,
      currentUrl: currentUrl,
      serverBaseUrl: serverBaseUrl,
      onSelect: (url) async {
        DialogUtils.showLoadingDialog(context: context, message: '更新中...');

        ApiResponse<void> updateResp;
        if (type == ImageSelectorType.poster && !isDesktop && selectedSeason != null) {
          // 移动端更换海报 -> 更新季度海报
          updateResp = await service.updateSeasonPoster(
            tvShow.id,
            selectedSeason.id,
            posterPath: url,
          );
        } else if (type == ImageSelectorType.poster) {
          // PC端更换海报 -> 更新剧集主海报
          updateResp = await service.updateTvShowPoster(tvShow.id, posterPath: url);
        } else {
          // 更换背景图 -> 更新剧集主背景图
          updateResp = await service.updateTvShowPoster(tvShow.id, backdropPath: url);
        }

        if (context.mounted) {
          Navigator.pop(context);
        }
        if (!context.mounted) return;

        if (updateResp.isSuccess) {
          ref.invalidate(tvShowDetailProvider(widget.tvShowId));
          ref.read(postersProvider.notifier).refresh();
          DialogUtils.showToast(context: context, message: '更新成功');
        } else {
          DialogUtils.showToast(
            context: context,
            message: updateResp.error ?? '更新失败',
            isError: true,
          );
        }
      },
    );
  }

  Future<void> _scrapeTvShow(BuildContext context, int id) async {
    final service = ref.read(mediaServiceProvider);
    if (service == null) {
      DialogUtils.showToast(context: context, message: '未连接到服务器', isError: true);
      return;
    }

    final confirmed = await DialogUtils.showConfirmDialog(
      context: context,
      title: '重新刮削',
      content: '将从刮削源重新拉取元数据（海报、简介、演员表等）。是否继续？',
      confirmText: '开始',
    );

    if (confirmed != true || !context.mounted) return;

    DialogUtils.showLoadingDialog(context: context, message: '正在刮削...');

    final resp = await service.scrapeTvShow(id);

    if (context.mounted) {
      Navigator.pop(context);
    }
    if (!context.mounted) return;

    if (resp.isSuccess) {
      ref.invalidate(tvShowDetailProvider(id));
      DialogUtils.showToast(context: context, message: '刮削完成');
      return;
    }

    DialogUtils.showToast(
      context: context,
      message: resp.error ?? '刮削失败',
      isError: true,
    );
  }

  Future<void> _syncTvShowSeasons(BuildContext context, int id, String? tmdbId) async {
    final service = ref.read(mediaServiceProvider);
    if (service == null) {
      DialogUtils.showToast(context: context, message: '未连接到服务器', isError: true);
      return;
    }

    final confirmed = await DialogUtils.showConfirmDialog(
      context: context,
      title: '同步季度',
      content: '将从 TMDB 重新拉取完整的季度和剧集元数据。是否继续？',
      confirmText: '开始',
    );

    if (confirmed != true || !context.mounted) return;

    DialogUtils.showLoadingDialog(context: context, message: '正在同步...');

    final resp = await service.syncTvShowSeasons(
      id,
      tmdbId: tmdbId != null ? int.tryParse(tmdbId) : null,
    );

    if (context.mounted) {
      Navigator.pop(context);
    }
    if (!context.mounted) return;

    if (resp.isSuccess) {
      ref.invalidate(tvShowDetailProvider(id));
      DialogUtils.showToast(context: context, message: '同步完成');
      return;
    }

    DialogUtils.showToast(
      context: context,
      message: resp.error ?? '同步失败',
      isError: true,
    );
  }

  /// 构建文件信息区
  Widget _buildFileInfoSection(
    BuildContext context,
    ThemeData theme,
    TvShow tvShow,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 分割线
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Divider(
            color: Colors.black.withValues(alpha: 0.1),
            height: 48,
          ),
        ),

        // 文件信息
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '媒体信息',
                style: TextStyle(
                  color: Colors.black.withValues(alpha: 0.5),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'TMDB ID: ${tvShow.tmdbId ?? "未知"} | IMDB: ${tvShow.imdbId ?? "未知"}',
                style: TextStyle(
                  color: Colors.black.withValues(alpha: 0.3),
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              ),
              if (tvShow.genres != null && tvShow.genres!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '类型: ${tvShow.genres!.join(", ")}',
                    style: TextStyle(
                      color: Colors.black.withValues(alpha: 0.3),
                      fontSize: 11,
                    ),
                  ),
                ),
              if (tvShow.storageName != null && tvShow.storageName!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '存储: ${tvShow.storageName}',
                    style: TextStyle(
                      color: Colors.black.withValues(alpha: 0.3),
                      fontSize: 11,
                    ),
                  ),
                ),
              if (tvShow.sourceFolders != null &&
                  tvShow.sourceFolders!.isNotEmpty)
                ...tvShow.sourceFolders!.map(
                  (folder) => Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '路径: $folder',
                      style: TextStyle(
                        color: Colors.black.withValues(alpha: 0.3),
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 剧集水平滚动卡片列表 - 直接使用数据
class _EpisodesCarouselDirect extends StatefulWidget {
  final List<Episode> episodes;
  final int tvShowId;
  final int seasonId;
  final String? tvShowName;
  final String? serverBaseUrl;
  final String? fallbackImageUrl;
  final ScrollController scrollController;

  static const double _minItemWidth = 160.0;
  static const double _itemSpacing = 16.0;
  static const double _horizontalPadding = 12.0;

  const _EpisodesCarouselDirect({
    required this.episodes,
    required this.tvShowId,
    required this.seasonId,
    this.tvShowName,
    required this.serverBaseUrl,
    this.fallbackImageUrl,
    required this.scrollController,
  });

  @override
  State<_EpisodesCarouselDirect> createState() =>
      _EpisodesCarouselDirectState();
}

class _EpisodesCarouselDirectState extends State<_EpisodesCarouselDirect> {
  double? _lastWidth;

  void _alignScrollPosition(double availableWidth) {
    if (!widget.scrollController.hasClients) return;
    final pos = widget.scrollController.position;
    if (pos.pixels <= pos.minScrollExtent) return;

    final itemCount = ((availableWidth + _EpisodesCarouselDirect._itemSpacing) /
            (_EpisodesCarouselDirect._minItemWidth +
                _EpisodesCarouselDirect._itemSpacing))
        .floor();
    final itemWidth = itemCount > 0
        ? (availableWidth -
                (itemCount - 1) * _EpisodesCarouselDirect._itemSpacing) /
            itemCount
        : _EpisodesCarouselDirect._minItemWidth;
    final pageSize =
        (itemCount - 1) * (itemWidth + _EpisodesCarouselDirect._itemSpacing);

    if (pageSize > 0) {
      // 对齐到最近的页边界
      final currentPage = (pos.pixels / pageSize).round();
      final alignedPosition =
          (currentPage * pageSize).clamp(pos.minScrollExtent, pos.maxScrollExtent);
      if ((pos.pixels - alignedPosition).abs() > 1) {
        widget.scrollController.jumpTo(alignedPosition);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!WindowControls.isDesktop) {
      return _buildList(_EpisodesCarouselDirect._minItemWidth);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth -
            _EpisodesCarouselDirect._horizontalPadding * 2;

        // 窗口大小变化时重新对齐
        if (_lastWidth != null && _lastWidth != availableWidth) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _alignScrollPosition(availableWidth);
          });
        }
        _lastWidth = availableWidth;

        final itemCount = ((availableWidth +
                    _EpisodesCarouselDirect._itemSpacing) /
                (_EpisodesCarouselDirect._minItemWidth +
                    _EpisodesCarouselDirect._itemSpacing))
            .floor();
        final itemWidth = itemCount > 0
            ? (availableWidth -
                    (itemCount - 1) * _EpisodesCarouselDirect._itemSpacing) /
                itemCount
            : _EpisodesCarouselDirect._minItemWidth;
        return _buildList(itemWidth);
      },
    );
  }

  Widget _buildList(double itemWidth) {
    return SizedBox(
      height: 140,
      child: ListView.separated(
        controller: widget.scrollController,
        physics: ScrollableRowWithArrows.disableManualScroll
            ? const NeverScrollableScrollPhysics()
            : null,
        padding: const EdgeInsets.symmetric(
            horizontal: _EpisodesCarouselDirect._horizontalPadding),
        scrollDirection: Axis.horizontal,
        itemCount: widget.episodes.length,
        separatorBuilder: (_, __) =>
            const SizedBox(width: _EpisodesCarouselDirect._itemSpacing),
        itemBuilder: (context, index) {
          final episode = widget.episodes[index];
          return _EpisodeCard(
            episode: episode,
            tvShowId: widget.tvShowId,
            seasonId: widget.seasonId,
            tvShowName: widget.tvShowName,
            serverBaseUrl: widget.serverBaseUrl,
            fallbackImageUrl: widget.fallbackImageUrl,
            episodes: widget.episodes,
            width: itemWidth,
          );
        },
      ),
    );
  }
}

/// 剧集水平滚动卡片列表
class _EpisodesCarousel extends ConsumerStatefulWidget {
  final int tvShowId;
  final int seasonId;
  final String? tvShowName;
  final String? fallbackImageUrl;
  final ScrollController scrollController;

  static const double _minItemWidth = 160.0;
  static const double _itemSpacing = 16.0;
  static const double _horizontalPadding = 12.0;

  const _EpisodesCarousel({
    required this.tvShowId,
    required this.seasonId,
    this.tvShowName,
    this.fallbackImageUrl,
    required this.scrollController,
  });

  @override
  ConsumerState<_EpisodesCarousel> createState() => _EpisodesCarouselState();
}

class _EpisodesCarouselState extends ConsumerState<_EpisodesCarousel> {
  double? _lastWidth;

  void _alignScrollPosition(double availableWidth) {
    if (!widget.scrollController.hasClients) return;
    final pos = widget.scrollController.position;
    if (pos.pixels <= pos.minScrollExtent) return;

    final itemCount = ((availableWidth + _EpisodesCarousel._itemSpacing) /
            (_EpisodesCarousel._minItemWidth + _EpisodesCarousel._itemSpacing))
        .floor();
    final itemWidth = itemCount > 0
        ? (availableWidth - (itemCount - 1) * _EpisodesCarousel._itemSpacing) /
            itemCount
        : _EpisodesCarousel._minItemWidth;
    final pageSize =
        (itemCount - 1) * (itemWidth + _EpisodesCarousel._itemSpacing);

    if (pageSize > 0) {
      final currentPage = (pos.pixels / pageSize).round();
      final alignedPosition =
          (currentPage * pageSize).clamp(pos.minScrollExtent, pos.maxScrollExtent);
      if ((pos.pixels - alignedPosition).abs() > 1) {
        widget.scrollController.jumpTo(alignedPosition);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final serverBaseUrl = ref.watch(serverUrlProvider);
    final episodesAsync = ref.watch(
      seasonEpisodesProvider(
          (tvShowId: widget.tvShowId, seasonId: widget.seasonId)),
    );

    return episodesAsync.when(
      loading:
          () => const SizedBox(
            height: 140,
            child: Center(
              child: CircularProgressIndicator(color: Colors.black),
            ),
          ),
      error:
          (error, stack) => Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              '加载失败: $error',
              style: TextStyle(color: Colors.black.withValues(alpha: 0.7)),
            ),
          ),
      data: (episodes) {
        if (episodes == null || episodes.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              '暂无剧集',
              style: TextStyle(color: Colors.black.withValues(alpha: 0.7)),
            ),
          );
        }

        if (!WindowControls.isDesktop) {
          return _buildList(
              episodes, serverBaseUrl, _EpisodesCarousel._minItemWidth);
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            final availableWidth = constraints.maxWidth -
                _EpisodesCarousel._horizontalPadding * 2;

            if (_lastWidth != null && _lastWidth != availableWidth) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _alignScrollPosition(availableWidth);
              });
            }
            _lastWidth = availableWidth;

            final itemCount = ((availableWidth + _EpisodesCarousel._itemSpacing) /
                    (_EpisodesCarousel._minItemWidth +
                        _EpisodesCarousel._itemSpacing))
                .floor();
            final itemWidth = itemCount > 0
                ? (availableWidth -
                        (itemCount - 1) * _EpisodesCarousel._itemSpacing) /
                    itemCount
                : _EpisodesCarousel._minItemWidth;
            return _buildList(episodes, serverBaseUrl, itemWidth);
          },
        );
      },
    );
  }

  Widget _buildList(
      List<Episode> episodes, String? serverBaseUrl, double itemWidth) {
    return SizedBox(
      height: 140,
      child: ListView.separated(
        controller: widget.scrollController,
        physics: ScrollableRowWithArrows.disableManualScroll
            ? const NeverScrollableScrollPhysics()
            : null,
        padding: const EdgeInsets.symmetric(
            horizontal: _EpisodesCarousel._horizontalPadding),
        scrollDirection: Axis.horizontal,
        itemCount: episodes.length,
        separatorBuilder: (_, __) =>
            const SizedBox(width: _EpisodesCarousel._itemSpacing),
        itemBuilder: (context, index) {
          final episode = episodes[index];
          return _EpisodeCard(
            episode: episode,
            tvShowId: widget.tvShowId,
            seasonId: widget.seasonId,
            tvShowName: widget.tvShowName,
            serverBaseUrl: serverBaseUrl,
            fallbackImageUrl: widget.fallbackImageUrl,
            episodes: episodes,
            width: itemWidth,
          );
        },
      ),
    );
  }
}

/// 单集卡片 - 竖向布局
class _EpisodeCard extends ConsumerWidget {
  final Episode episode;
  final int tvShowId;
  final int seasonId;
  final String? tvShowName;
  final String? serverBaseUrl;
  final String? fallbackImageUrl;
  final List<Episode>? episodes;
  final double width;

  const _EpisodeCard({
    required this.episode,
    required this.tvShowId,
    required this.seasonId,
    this.tvShowName,
    required this.serverBaseUrl,
    this.fallbackImageUrl,
    this.episodes,
    this.width = 160,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final thumbnailHeight = width * 90 / 160; // 保持 16:9 比例
    return GestureDetector(
      onTap: episode.hasFile ? () => _playEpisode(context, ref) : null,
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 缩略图
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: _buildThumbnail(thumbnailHeight),
                ),

                // 时长标签
                if (episode.runtime != null)
                  Positioned(
                    right: 6,
                    bottom: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        episode.formattedRuntime,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ),

                // 无文件遮罩
                if (!episode.hasFile)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text(
                          '无文件',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ),

                // 播放图标
                if (episode.hasFile)
                  Positioned.fill(
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.play_arrow,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),

            // 标题
            Expanded(
              child: Text(
                '${episode.episodeNumber}. ${episode.name ?? "第${episode.episodeNumber}集"}',
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _playEpisode(BuildContext context, WidgetRef ref) async {
    final service = ref.read(mediaServiceProvider);
    int? position;

    if (service != null) {
      final historyResp = await service.getWatchProgress('tv', tvShowId);
      if (historyResp.isSuccess &&
          historyResp.data != null &&
          historyResp.data!.episodeId == episode.id &&
          !historyResp.data!.completed) {
        position = historyResp.data!.position;
      }
    }

    if (!context.mounted) return;
    final title =
        tvShowName != null
            ? '$tvShowName - ${episode.displayTitle}'
            : episode.displayTitle;
    debugPrint('[_playEpisode] before push');
    await context.push(
      '/player/episode/$tvShowId/$seasonId/${episode.id}',
      extra: {'position': position, 'title': title, 'episodes': episodes},
    );
    debugPrint('[_playEpisode] after push, waiting 500ms');
    await Future.delayed(const Duration(milliseconds: 500));
    debugPrint('[_playEpisode] calling refresh');
    ref.read(watchHistoryProvider.notifier).refresh();
  }

  Widget _buildThumbnail(double height) {
    final hasStill = episode.stillPath != null && episode.stillPath!.isNotEmpty;
    final imageUrl = hasStill ? episode.stillPath! : fallbackImageUrl;
    if (imageUrl != null && imageUrl.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: ImageProxy.proxyTMDBIfNeeded(imageUrl, serverBaseUrl),
        width: width,
        height: height,
        fit: BoxFit.cover,
        errorWidget: (_, __, ___) => _buildPlaceholder(height),
      );
    }
    return _buildPlaceholder(height);
  }

  Widget _buildPlaceholder(double height) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        Icons.play_circle_outline,
        color: Colors.black.withValues(alpha: 0.3),
        size: 32,
      ),
    );
  }
}

/// 季度标签（含播放源数量角标和下拉箭头）
class _SeasonTabLabel extends ConsumerWidget {
  final int tvShowId;
  final Season season;
  final bool isSelected;
  final bool isSingleSeason;

  const _SeasonTabLabel({
    required this.tvShowId,
    required this.season,
    required this.isSelected,
    required this.isSingleSeason,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sourceGroupsAsync = ref.watch(
      seasonSourceGroupsProvider((tvShowId: tvShowId, seasonId: season.id)),
    );

    return sourceGroupsAsync.when(
      loading: () => _buildLabel(context, null),
      error: (_, __) => _buildLabel(context, null),
      data: (groups) => _buildLabel(context, groups),
    );
  }

  Widget _buildLabel(BuildContext context, List<SourceGroup>? groups) {
    final hasMultipleSources = groups != null && groups.length > 1;
    final sourceCount = groups?.length ?? 0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '第 ${season.seasonNumber} 季',
          style: TextStyle(
            color: isSelected ? Colors.black : Colors.grey,
            fontSize: 18.0,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.normal,
          ),
        ),
        if (hasMultipleSources) ...[
          const SizedBox(width: 2),
          // 播放源数量角标
          Transform.translate(
            offset: const Offset(0, -6),
            child: Text(
              '$sourceCount',
              style: TextStyle(
                color: isSelected ? Colors.black : Colors.grey,
                fontSize: 11.0,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 4),
          // 下拉箭头
          GestureDetector(
            onTap: () => _showSourceGroupsDialog(context, groups),
            child: Icon(
              Icons.arrow_drop_down,
              color: isSelected ? Colors.black : Colors.grey,
              size: 20,
            ),
          ),
        ],
      ],
    );
  }

  void _showSourceGroupsDialog(
    BuildContext context,
    List<SourceGroup>? groups,
  ) {
    if (groups == null || groups.isEmpty) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder:
          (context) => _SourceGroupsSheet(
            tvShowId: tvShowId,
            seasonId: season.id,
            seasonName: isSingleSeason ? '第一季' : season.displayName,
            groups: groups,
          ),
    );
  }
}

/// 播放源分组列表弹窗
class _SourceGroupsSheet extends ConsumerWidget {
  final int tvShowId;
  final int seasonId;
  final String seasonName;
  final List<SourceGroup> groups;

  const _SourceGroupsSheet({
    required this.tvShowId,
    required this.seasonId,
    required this.seasonName,
    required this.groups,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 标题栏
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              children: [
                Text(
                  '$seasonName 播放源',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.pop(context),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // 播放源列表
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: groups.length,
              separatorBuilder:
                  (_, __) =>
                      const Divider(height: 1, indent: 20, endIndent: 20),
              itemBuilder: (context, index) {
                final group = groups[index];
                return _SourceGroupTile(
                  group: group,
                  onTap: () => _onSelectSource(context, ref, group),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onSelectSource(
    BuildContext context,
    WidgetRef ref,
    SourceGroup group,
  ) async {
    if (group.isPrimary) {
      Navigator.pop(context);
      return;
    }

    final service = ref.read(mediaServiceProvider);
    if (service == null) return;

    Navigator.pop(context);

    final response = await service.setSeasonPrimarySource(
      tvShowId,
      seasonId,
      group.folderPath,
    );
    if (response.isSuccess) {
      // 刷新播放源分组数据
      ref.invalidate(
        seasonSourceGroupsProvider((tvShowId: tvShowId, seasonId: seasonId)),
      );
      // 刷新剧集详情（包含 episodes 数据，下载列表需要）
      ref.invalidate(tvShowDetailProvider(tvShowId));
    }
  }
}

/// 单个播放源分组项
class _SourceGroupTile extends StatelessWidget {
  final SourceGroup group;
  final VoidCallback onTap;

  const _SourceGroupTile({required this.group, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      title: Text(
        group.displayLabel,
        style: TextStyle(
          fontSize: 15,
          fontWeight: group.isPrimary ? FontWeight.w500 : FontWeight.w500,
          color: group.isPrimary ? Colors.blue : Colors.black,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          // 存储源名称
          if (group.storageName != null && group.storageName!.isNotEmpty)
            Row(
              children: [
                Icon(Icons.storage, size: 14, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text(
                  group.storageName!,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          const SizedBox(height: 2),
          // 文件夹路径
          Row(
            children: [
              Icon(Icons.folder_outlined, size: 14, color: Colors.grey[600]),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  group.folderPath,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          // 文件数量和大小
          Row(
            children: [
              Icon(
                Icons.video_file_outlined,
                size: 14,
                color: Colors.grey[600],
              ),
              const SizedBox(width: 4),
              Text(
                '${group.fileCount} 个文件',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              const SizedBox(width: 12),
              Text(
                group.formattedSize,
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ),
        ],
      ),
      trailing:
          group.isPrimary
              ? const Icon(Icons.check_circle, color: Colors.blue)
              : const Icon(Icons.chevron_right, color: Colors.grey),
      onTap: onTap,
    );
  }
}

class _EpisodesScrollButtons extends StatefulWidget {
  final ScrollController controller;

  static const double _minItemWidth = 160.0;
  static const double _itemSpacing = 16.0;
  static const double _horizontalPadding = 12.0;

  const _EpisodesScrollButtons({super.key, required this.controller});

  @override
  State<_EpisodesScrollButtons> createState() => _EpisodesScrollButtonsState();
}

class _EpisodesScrollButtonsState extends State<_EpisodesScrollButtons> {
  bool _canScrollLeft = false;
  bool _canScrollRight = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_updateScrollState);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateScrollState();
      // 延迟再次更新，确保剧集列表完全渲染后获取正确的 maxScrollExtent
      WidgetsBinding.instance.addPostFrameCallback((_) => _updateScrollState());
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_updateScrollState);
    super.dispose();
  }

  void _updateScrollState() {
    if (!mounted || !widget.controller.hasClients) return;
    final pos = widget.controller.position;
    setState(() {
      _canScrollLeft = pos.pixels > pos.minScrollExtent;
      _canScrollRight = pos.pixels < pos.maxScrollExtent;
    });
  }

  void _scroll(bool forward) {
    final pos = widget.controller.position;
    final viewportWidth = pos.viewportDimension;
    // 计算当前视口能显示多少个卡片
    final availableWidth = viewportWidth - _EpisodesScrollButtons._horizontalPadding * 2;
    final itemCount = ((availableWidth + _EpisodesScrollButtons._itemSpacing) /
            (_EpisodesScrollButtons._minItemWidth + _EpisodesScrollButtons._itemSpacing))
        .floor();
    final itemWidth = itemCount > 0
        ? (availableWidth - (itemCount - 1) * _EpisodesScrollButtons._itemSpacing) / itemCount
        : _EpisodesScrollButtons._minItemWidth;
    // 滚动距离 = (itemCount - 1) 个卡片的宽度，让最后一个变成第一个
    final scrollDistance = (itemCount - 1) * (itemWidth + _EpisodesScrollButtons._itemSpacing);
    final target = (pos.pixels + (forward ? scrollDistance : -scrollDistance))
        .clamp(pos.minScrollExtent, pos.maxScrollExtent);
    widget.controller.animateTo(
      target,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_canScrollLeft && !_canScrollRight) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildButton(Icons.chevron_left, _canScrollLeft, () => _scroll(false)),
        const SizedBox(width: 4),
        _buildButton(Icons.chevron_right, _canScrollRight, () => _scroll(true)),
      ],
    );
  }

  Widget _buildButton(IconData icon, bool enabled, VoidCallback onTap) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: enabled
              ? Colors.black.withValues(alpha: 0.1)
              : Colors.black.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(
          icon,
          color: enabled
              ? Colors.black.withValues(alpha: 0.7)
              : Colors.black.withValues(alpha: 0.3),
          size: 20,
        ),
      ),
    );
  }
}
