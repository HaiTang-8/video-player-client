import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_back_button.dart';
import '../../core/widgets/scrollable_row_with_arrows.dart';
import '../../core/widgets/cast_avatar.dart';
import '../../core/widgets/desktop_app_bar.dart';
import '../../core/widgets/detail_hero_background.dart';
import '../../core/widgets/image_selector_sheet.dart';
import '../../core/widgets/dialog_utils.dart';
import '../../core/widgets/media_delete_action.dart';
import '../../core/window/window_controls.dart';
import '../../core/widgets/skeleton_loader.dart';
import '../../core/widgets/overview_preview_text.dart';
import '../../data/models/models.dart';
import '../../providers/providers.dart';
import '../storages/storage_browse_screen.dart';

/// 电影详情页面
class MovieDetailScreen extends ConsumerStatefulWidget {
  final int movieId;

  const MovieDetailScreen({super.key, required this.movieId});

  @override
  ConsumerState<MovieDetailScreen> createState() => _MovieDetailScreenState();
}

class _MovieDetailScreenState extends ConsumerState<MovieDetailScreen>
    with DetailHeroPaletteMixin<MovieDetailScreen> {
  Movie? _movie;
  final _castScrollController = ScrollController();
  WatchHistoryItem? _watchHistory;
  bool _historyLoaded = false;
  bool _showSolidAppBar = false;

  void _invalidateMovieDetail() {
    ref.invalidate(movieDetailProvider(widget.movieId));
  }

  WatchProgressKey get _watchProgressKey => (
    mediaType: 'movie',
    mediaId: widget.movieId,
    episodeId: null,
    seasonId: null,
  );

  WatchHistoryItem? get _currentWatchHistory {
    final local = ref.watch(watchProgressProvider)[_watchProgressKey];
    return local ?? _watchHistory;
  }

  @override
  void initState() {
    super.initState();
  }

  Future<void> _loadWatchHistory() async {
    final service = ref.read(mediaServiceProvider);
    if (service == null) return;
    final tmdbId = int.tryParse(_movie?.tmdbId ?? '');
    final resp = await service.getWatchProgress(
      'movie',
      widget.movieId,
      tmdbId: tmdbId,
    );
    if (!mounted) return;
    if (resp.isSuccess && resp.data != null && !resp.data!.completed) {
      ref
          .read(watchProgressProvider.notifier)
          .upsert(_watchProgressKey, resp.data!);
      setState(() => _watchHistory = resp.data);
    } else {
      ref.read(watchProgressProvider.notifier).remove(_watchProgressKey);
      setState(() => _watchHistory = null);
    }
  }

  @override
  void dispose() {
    _castScrollController.dispose();
    super.dispose();
  }

  bool _handleMainScroll(ScrollNotification notification) {
    if (notification.depth != 0 || notification.metrics.axis != Axis.vertical) {
      return false;
    }

    final shouldShowSolidAppBar =
        notification.metrics.maxScrollExtent > 0 &&
        notification.metrics.pixels >=
            notification.metrics.maxScrollExtent - 16;
    if (shouldShowSolidAppBar == _showSolidAppBar) {
      return false;
    }

    setState(() {
      _showSolidAppBar = shouldShowSolidAppBar;
    });
    return false;
  }

  @override
  String get heroPaletteDebugLabel =>
      'screen=movie_detail movieId=${widget.movieId}';

  DetailHeroImage _heroImageFor(
    Movie movie,
    Size screenSize,
    String? serverBaseUrl, {
    required bool isDesktop,
  }) {
    return DetailHeroImage.resolve(
      posterPath: movie.posterPath,
      backdropPath: movie.backdropPath,
      screenSize: screenSize,
      serverBaseUrl: serverBaseUrl,
      isDesktop: isDesktop,
    );
  }

  @override
  Widget build(BuildContext context) {
    final movieAsync = ref.watch(movieDetailProvider(widget.movieId));
    final baseTheme = Theme.of(context);
    final screenSize = MediaQuery.sizeOf(context);
    final isDesktop = WindowControls.isDesktop;
    final serverBaseUrl = ref.watch(serverUrlProvider);
    final accessToken = ref.watch(authProvider).tokens?.accessToken;

    return Theme(
      data: isDesktop ? baseTheme : AppTheme.mobileDetailDarkTheme(baseTheme),
      child: Builder(
        builder: (context) {
          final theme = Theme.of(context);
          final resolvedMovie = movieAsync.asData?.value;
          final resolvedHeroImage =
              resolvedMovie == null
                  ? null
                  : _heroImageFor(
                    resolvedMovie,
                    screenSize,
                    serverBaseUrl,
                    isDesktop: isDesktop,
                  );
          final targetBackgroundColor = heroBackgroundColor(
            context,
            resolvedHeroImage,
            isDesktop: isDesktop,
          );

          return TweenAnimationBuilder<Color?>(
            tween: ColorTween(end: targetBackgroundColor),
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOut,
            builder: (context, animatedBackgroundColor, _) {
              final detailBackgroundColor =
                  animatedBackgroundColor ?? targetBackgroundColor;
              final detailSurfaceColor =
                  isDesktop
                      ? detailBackgroundColor
                      : DetailHeroBackground.surfaceColorFor(
                        context,
                        detailBackgroundColor,
                      );

              return AnnotatedRegion<SystemUiOverlayStyle>(
                value: SystemUiOverlayStyle.light,
                child: Scaffold(
                  backgroundColor: detailSurfaceColor,
                  appBar:
                      isDesktop
                          ? movieAsync.when(
                            loading:
                                () => DesktopAppBar(
                                  title: const Text('加载中...'),
                                  onBack: () => context.pop(),
                                ),
                            error:
                                (error, stack) => DesktopAppBar(
                                  title: const Text('电影详情'),
                                  onBack: () => context.pop(),
                                  actions: [
                                    IconButton(
                                      icon: const Icon(Icons.refresh),
                                      onPressed: _invalidateMovieDetail,
                                    ),
                                  ],
                                ),
                            data:
                                (movie) => DesktopAppBar(
                                  title: Text(movie?.title ?? '电影详情'),
                                  onBack: () => context.pop(),
                                  actions: _buildDesktopActions(movie),
                                ),
                          )
                          : null,
                  body: movieAsync.when(
                    loading: () => const DetailSkeletonLoader.movie(),
                    error:
                        (error, stack) => AppErrorWidget(
                          message: error.toString(),
                          onRetry: _invalidateMovieDetail,
                        ),
                    data: (movie) {
                      if (movie == null) {
                        return const AppErrorWidget(message: '电影不存在');
                      }
                      _movie = movie;
                      final heroImage =
                          resolvedHeroImage ??
                          _heroImageFor(
                            movie,
                            screenSize,
                            serverBaseUrl,
                            isDesktop: isDesktop,
                          );
                      resolveHeroPalette(
                        heroImage,
                        accessToken,
                        isDesktop: isDesktop,
                      );
                      if (!_historyLoaded) {
                        _historyLoaded = true;
                        _loadWatchHistory();
                      }

                      final cast =
                          (movie.castDetail != null &&
                                  movie.castDetail!.isNotEmpty)
                              ? movie.castDetail!
                              : (movie.cast != null
                                  ? movie.cast!
                                      .where((e) => e.trim().isNotEmpty)
                                      .map((e) => CastMember(name: e.trim()))
                                      .toList()
                                  : const <CastMember>[]);

                      if (isDesktop) {
                        return CustomScrollView(
                          slivers: [
                            SliverToBoxAdapter(
                              child: DetailHeroBackground(
                                heroImage: heroImage,
                                accessToken: accessToken,
                                backgroundColor: detailBackgroundColor,
                                surfaceColor: detailSurfaceColor,
                                isDesktop: true,
                                content: _buildDesktopHeroContent(
                                  context,
                                  movie,
                                ),
                              ),
                            ),
                            if (cast.isNotEmpty)
                              SliverToBoxAdapter(
                                child: _buildCastSection(
                                  context,
                                  theme,
                                  cast,
                                  serverBaseUrl,
                                  accessToken,
                                ),
                              ),
                            SliverToBoxAdapter(
                              child: _buildFileInfoSection(
                                context,
                                theme,
                                movie,
                              ),
                            ),
                            const SliverToBoxAdapter(
                              child: SizedBox(height: 32),
                            ),
                          ],
                        );
                      }

                      return Stack(
                        children: [
                          NotificationListener<ScrollNotification>(
                            onNotification: _handleMainScroll,
                            child: CustomScrollView(
                              slivers: [
                                SliverToBoxAdapter(
                                  child: DetailHeroBackground(
                                    heroImage: heroImage,
                                    accessToken: accessToken,
                                    backgroundColor: detailBackgroundColor,
                                    surfaceColor: detailSurfaceColor,
                                    isDesktop: false,
                                    content: _buildMobileHeroContent(
                                      context,
                                      movie,
                                    ),
                                  ),
                                ),
                                if (movie.overview != null &&
                                    movie.overview!.isNotEmpty)
                                  SliverToBoxAdapter(
                                    child: _buildOverviewSection(movie),
                                  ),
                                if (cast.isNotEmpty)
                                  SliverToBoxAdapter(
                                    child: _buildCastSection(
                                      context,
                                      theme,
                                      cast,
                                      serverBaseUrl,
                                      accessToken,
                                    ),
                                  ),
                                SliverToBoxAdapter(
                                  child: _buildFileInfoSection(
                                    context,
                                    theme,
                                    movie,
                                  ),
                                ),
                                const SliverToBoxAdapter(
                                  child: SizedBox(height: 32),
                                ),
                              ],
                            ),
                          ),
                          _buildMobileAppBar(
                            context,
                            movie,
                            solid: _showSolidAppBar,
                          ),
                        ],
                      );
                    },
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildDesktopHeroContent(BuildContext context, Movie movie) {
    final colors = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          movie.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: colors.textPrimary,
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
                  _buildPrimaryMetadataRow(context, movie),
                  if ((movie.genres != null && movie.genres!.isNotEmpty) ||
                      movie.fileSize != null) ...[
                    const SizedBox(height: 6),
                    _buildSecondaryMetadataRow(context, movie),
                  ],
                  if (movie.overview != null && movie.overview!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      movie.overview!,
                      style: TextStyle(
                        color: colors.textPrimary.withValues(alpha: 0.8),
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

  Widget _buildMobileHeroContent(BuildContext context, Movie movie) {
    final colors = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 第一行：标题
        Text(
          movie.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        _buildPrimaryMetadataRow(context, movie),
        if ((movie.genres != null && movie.genres!.isNotEmpty) ||
            movie.fileSize != null) ...[
          const SizedBox(height: 6),
          _buildSecondaryMetadataRow(context, movie),
        ],
        const SizedBox(height: 20),
        _buildFullWidthPlayButton(context),
      ],
    );
  }

  Widget _buildPrimaryMetadataRow(BuildContext context, Movie movie) {
    final colors = context.appColors;
    final items = <Widget>[];
    final textStyle = TextStyle(
      color: colors.textPrimary.withValues(alpha: 0.7),
      fontSize: 14,
      fontWeight: FontWeight.bold,
    );
    final iconColor = colors.textPrimary.withValues(alpha: 0.5);

    if (movie.rating != null && movie.rating! > 0) {
      items.add(_buildTmdbRatingBadge(context, movie.rating!, textStyle));
    }

    // 发布时间
    if (movie.releaseDate != null || movie.year != null) {
      if (items.isNotEmpty) items.add(_buildDivider(context));
      final dateText =
          movie.releaseDate != null
              ? '${movie.releaseDate!.year}-${movie.releaseDate!.month.toString().padLeft(2, '0')}-${movie.releaseDate!.day.toString().padLeft(2, '0')}'
              : '${movie.year}';
      items.add(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(shadcn.LucideIcons.calendar, size: 16, color: iconColor),
            const SizedBox(width: 4),
            Text(dateText, style: textStyle),
          ],
        ),
      );
    }

    if (movie.runtime != null) {
      if (items.isNotEmpty) items.add(_buildDivider(context));
      items.add(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(shadcn.LucideIcons.clock, size: 16, color: iconColor),
            const SizedBox(width: 4),
            Text(movie.formattedRuntime, style: textStyle),
          ],
        ),
      );
    }

    return Wrap(spacing: 0, runSpacing: 6, children: items);
  }

  Widget _buildSecondaryMetadataRow(BuildContext context, Movie movie) {
    final colors = context.appColors;
    final items = <Widget>[];
    final textStyle = TextStyle(
      color: colors.textPrimary.withValues(alpha: 0.7),
      fontSize: 14,
      fontWeight: FontWeight.bold,
    );

    if (movie.genres != null && movie.genres!.isNotEmpty) {
      items.add(Text(movie.genres!.join(' / '), style: textStyle));
    }

    if (movie.fileSize != null) {
      if (items.isNotEmpty) items.add(_buildDivider(context));
      items.add(Text(movie.formattedFileSize, style: textStyle));
    }

    return Wrap(spacing: 0, runSpacing: 6, children: items);
  }

  Widget _buildDivider(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        '|',
        style: TextStyle(
          color: colors.textPrimary.withValues(alpha: 0.3),
          fontSize: 13,
        ),
      ),
    );
  }

  Widget _buildTmdbRatingBadge(
    BuildContext context,
    double rating,
    TextStyle textStyle,
  ) {
    const tmdbBackground = Color(0xFF032541);
    const tmdbAccent = Color(0xFF90CEA1);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: tmdbBackground,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: const Color(0x4090CEA1)),
          ),
          child: Text(
            'TMDB',
            style: TextStyle(
              color: tmdbAccent,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(rating.toStringAsFixed(1), style: textStyle),
      ],
    );
  }

  Widget _buildFullWidthPlayButton(BuildContext context) {
    final colors = context.appColors;
    final buttonBackground = colors.textPrimary;
    final buttonForeground = heroSurfaceColor(context);
    final history = _currentWatchHistory;
    String buttonText = '播放';
    if (history != null) {
      final pos = history.position;
      final m = (pos ~/ 60).toString().padLeft(2, '0');
      final s = (pos % 60).toString().padLeft(2, '0');
      buttonText = '续播 $m:$s';
    }
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: buttonBackground,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: () => _playMovie(context),
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.play_arrow, color: buttonForeground, size: 24),
                const SizedBox(width: 8),
                Text(
                  buttonText,
                  style: TextStyle(
                    color: buttonForeground,
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

  Widget _buildOverviewSection(Movie movie) {
    return Builder(
      builder: (context) {
        final colors = context.appColors;
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '剧情简介',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              OverviewPreviewText(
                title: movie.title,
                overview: movie.overview!,
                maxLines: 3,
                style: TextStyle(
                  color: colors.textPrimary.withValues(alpha: 0.7),
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  height: 1.6,
                ),
                linkStyle: TextStyle(
                  color: colors.textPrimary.withValues(alpha: 0.9),
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  height: 1.6,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMobileAppBar(
    BuildContext context,
    Movie movie, {
    required bool solid,
  }) {
    final colors = context.appColors;
    final hasFile = movie.filePath != null && movie.filePath!.isNotEmpty;
    final backgroundColor = heroSurfaceColor(context);

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        color: solid ? backgroundColor : Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: SizedBox(
            height: 44,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (solid)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 92),
                      child: Text(
                        movie.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: kAppBackButtonWidth,
                    child: AppBackButton(
                      onPressed: () => context.pop(),
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (hasFile)
                        CupertinoButton(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          onPressed: () => _downloadMovie(context, movie),
                          child: Icon(
                            shadcn.LucideIcons.circleArrowDown,
                            color: colors.textPrimary,
                            size: 22,
                          ),
                        ),
                      Builder(
                        builder:
                            (menuContext) => CupertinoButton(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              onPressed:
                                  () => _showMobileActionsMenu(
                                    menuContext,
                                    movie,
                                  ),
                              child: Icon(
                                CupertinoIcons.ellipsis,
                                color: colors.textPrimary,
                                size: 22,
                              ),
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _downloadMovie(BuildContext context, Movie movie) async {
    final confirmed = await DialogUtils.showConfirmDialog(
      context: context,
      title: '下载电影',
      content: '确定要下载「${movie.title}」吗？',
      confirmText: '下载',
    );
    if (confirmed != true || !context.mounted) return;

    final downloadManager = ref.read(downloadManagerProvider.notifier);
    downloadManager.addMovieDownload(movie: movie);
    DialogUtils.showToast(context: context, message: '已添加到下载队列');
  }

  List<Widget> _buildDesktopActions(Movie? movie) {
    if (movie == null) return [];
    final hasFile = movie.filePath != null && movie.filePath!.isNotEmpty;
    return [
      if (hasFile)
        IconButton(
          tooltip: '下载',
          icon: Icon(shadcn.LucideIcons.circleArrowDown),
          onPressed: () => _downloadMovie(context, movie),
        ),
      Builder(
        builder:
            (menuContext) => IconButton(
              tooltip: '更多',
              icon: const Icon(CupertinoIcons.ellipsis),
              onPressed: () => _showDesktopActionsMenu(menuContext, movie),
            ),
      ),
    ];
  }

  void _showMobileActionsMenu(BuildContext context, Movie movie) {
    shadcn.showDropdown(
      context: context,
      builder: (dropdownContext) {
        final noAccentTheme = shadcn.Theme.of(dropdownContext).copyWith(
          colorScheme:
              () => shadcn.Theme.of(
                dropdownContext,
              ).colorScheme.copyWith(accent: () => Colors.transparent),
        );
        return shadcn.Theme(
          data: noAccentTheme,
          child: shadcn.MenuGroup(
            direction: Axis.vertical,
            builder:
                (context, children) => shadcn.MenuPopup(children: children),
            children: [
              shadcn.MenuButton(
                leading: const Icon(CupertinoIcons.photo, size: 18),
                child: const Text('更换海报'),
                onPressed: (menuContext) {
                  shadcn.closeOverlay(menuContext);
                  _showImageSelector(context, movie, ImageSelectorType.poster);
                },
              ),
              shadcn.MenuButton(
                leading: const Icon(
                  CupertinoIcons.arrow_clockwise_circle,
                  size: 18,
                ),
                child: const Text('更新刮削'),
                onPressed: (menuContext) {
                  shadcn.closeOverlay(menuContext);
                  _updateMovieScraping(context, movie);
                },
              ),
              shadcn.MenuButton(
                leading: const Icon(CupertinoIcons.refresh, size: 18),
                child: const Text('刷新'),
                onPressed: (menuContext) {
                  shadcn.closeOverlay(menuContext);
                  _invalidateMovieDetail();
                },
              ),
              if (ref.read(authProvider).canManageMedia)
                mediaDeleteMenuButton(
                  context: dropdownContext,
                  label: '删除电影',
                  onPressed: () => _deleteMovie(context, movie),
                ),
            ],
          ),
        );
      },
    );
  }

  void _showDesktopActionsMenu(BuildContext context, Movie movie) {
    shadcn.showDropdown(
      context: context,
      builder: (dropdownContext) {
        final noAccentTheme = shadcn.Theme.of(dropdownContext).copyWith(
          colorScheme:
              () => shadcn.Theme.of(
                dropdownContext,
              ).colorScheme.copyWith(accent: () => Colors.transparent),
        );
        return shadcn.Theme(
          data: noAccentTheme,
          child: shadcn.MenuGroup(
            direction: Axis.vertical,
            builder:
                (context, children) => shadcn.MenuPopup(children: children),
            children: [
              shadcn.MenuButton(
                leading: const Icon(CupertinoIcons.photo, size: 18),
                child: const Text('更换海报'),
                onPressed: (menuContext) {
                  shadcn.closeOverlay(menuContext);
                  _showImageSelector(context, movie, ImageSelectorType.poster);
                },
              ),
              shadcn.MenuButton(
                leading: const Icon(
                  CupertinoIcons.photo_on_rectangle,
                  size: 18,
                ),
                child: const Text('更换背景图'),
                onPressed: (menuContext) {
                  shadcn.closeOverlay(menuContext);
                  _showImageSelector(
                    context,
                    movie,
                    ImageSelectorType.backdrop,
                  );
                },
              ),
              shadcn.MenuButton(
                leading: const Icon(
                  CupertinoIcons.arrow_clockwise_circle,
                  size: 18,
                ),
                child: const Text('更新刮削'),
                onPressed: (menuContext) {
                  shadcn.closeOverlay(menuContext);
                  _updateMovieScraping(context, movie);
                },
              ),
              shadcn.MenuButton(
                leading: const Icon(CupertinoIcons.refresh, size: 18),
                child: const Text('刷新'),
                onPressed: (menuContext) {
                  shadcn.closeOverlay(menuContext);
                  _invalidateMovieDetail();
                },
              ),
              if (ref.read(authProvider).canManageMedia)
                mediaDeleteMenuButton(
                  context: dropdownContext,
                  label: '删除电影',
                  onPressed: () => _deleteMovie(context, movie),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _deleteMovie(BuildContext context, Movie movie) async {
    final service = ref.read(mediaServiceProvider);
    if (service == null) return;
    final resp = await confirmAndDeleteMedia(
      context: context,
      ref: ref,
      title: '删除电影',
      content: '确定从媒体库删除「${movie.title}」吗？\n\n$mediaDeleteKeepFilesNote',
      request: () => service.deleteMovie(movie.id),
    );
    if (resp != null && context.mounted) context.pop();
  }

  /// 构建播放按钮
  Widget _buildPlayButton(BuildContext context) {
    final colors = context.appColors;
    final buttonBackground = colors.textPrimary;
    final buttonForeground = heroSurfaceColor(context);
    final history = _currentWatchHistory;
    String buttonText = '播放';
    if (history != null) {
      final pos = history.position;
      final m = (pos ~/ 60).toString().padLeft(2, '0');
      final s = (pos % 60).toString().padLeft(2, '0');
      buttonText = '续播 $m:$s';
    }
    return Material(
      color: buttonBackground,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: () => _playMovie(context),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: WindowControls.isDesktop ? 48 : 32,
            vertical: 14,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.play_arrow, color: buttonForeground, size: 24),
              const SizedBox(width: 8),
              Text(
                buttonText,
                style: TextStyle(
                  color: buttonForeground,
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

  Future<void> _playMovie(BuildContext context) async {
    final movie = _movie;
    if (movie == null) return;

    final service = ref.read(mediaServiceProvider);
    int? position;

    if (service != null) {
      final tmdbId = int.tryParse(movie.tmdbId ?? '');
      final historyResp = await service.getWatchProgress(
        'movie',
        movie.id,
        tmdbId: tmdbId,
      );
      if (historyResp.isSuccess && historyResp.data != null) {
        if (!historyResp.data!.completed) {
          position = historyResp.data!.position;
        }
      }
    }

    if (!context.mounted) return;
    await context.push(
      '/player/movie/${movie.id}',
      extra: {'position': position, 'title': movie.title},
    );
    if (!mounted) return;
    await _loadWatchHistory();
    ref.read(watchHistoryProvider.notifier).refresh();
  }

  /// 构建相关演员区
  Widget _buildCastSection(
    BuildContext context,
    ThemeData theme,
    List<CastMember> cast,
    String? serverBaseUrl,
    String? accessToken,
  ) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 12),
      child: ScrollableRowWithArrows(
        controller: _castScrollController,
        itemWidth: 80,
        itemSpacing: 4,
        title: Text(
          '相关演员',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        child: SizedBox(
          height: 120,
          child: ListView.separated(
            controller: _castScrollController,
            physics:
                ScrollableRowWithArrows.disableManualScroll
                    ? const NeverScrollableScrollPhysics()
                    : null,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            scrollDirection: Axis.horizontal,
            itemCount: cast.length,
            separatorBuilder: (_, _) => const SizedBox(width: 4),
            itemBuilder: (context, index) {
              return _buildCastCard(
                context,
                cast[index],
                serverBaseUrl,
                accessToken,
              );
            },
          ),
        ),
      ),
    );
  }

  /// 构建演员卡片
  Widget _buildCastCard(
    BuildContext context,
    CastMember member,
    String? serverBaseUrl,
    String? accessToken,
  ) {
    final colors = context.appColors;
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
              color: colors.textPrimary.withValues(alpha: 0.1),
              border: Border.all(
                color: colors.textPrimary.withValues(alpha: 0.2),
                width: 2,
              ),
            ),
            child: ClipOval(
              child: CastAvatar(
                size: 64,
                imageUrl: profileUrl,
                serverBaseUrl: serverBaseUrl,
                accessToken: accessToken,
                iconColor: colors.textPrimary.withValues(alpha: 0.5),
                iconSize: 32,
              ),
            ),
          ),
          const SizedBox(height: 8),

          // 姓名
          Text(
            name,
            style: TextStyle(
              color: colors.textPrimary,
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
                color: colors.textPrimary.withValues(alpha: 0.5),
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
    Movie movie,
    ImageSelectorType type,
  ) async {
    final service = ref.read(mediaServiceProvider);
    final serverBaseUrl = ref.read(serverUrlProvider);
    final accessToken = ref.read(authProvider).tokens?.accessToken;
    if (service == null) {
      DialogUtils.showToast(
        context: context,
        message: '未连接到服务器',
        isError: true,
      );
      return;
    }

    if (movie.tmdbId == null) {
      DialogUtils.showToast(
        context: context,
        message: '无 TMDB ID，无法获取图片',
        isError: true,
      );
      return;
    }

    DialogUtils.showLoadingDialog(context: context, message: '加载图片中...');

    final resp = await service.getMovieImages(movie.id);

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

    final images =
        type == ImageSelectorType.poster
            ? resp.data!.posters
            : resp.data!.backdrops;
    final currentUrl =
        type == ImageSelectorType.poster
            ? movie.posterPath
            : movie.backdropPath;

    showImageSelector(
      context: context,
      images: images,
      type: type,
      currentUrl: currentUrl,
      serverBaseUrl: serverBaseUrl,
      accessToken: accessToken,
      onSelect: (url) async {
        DialogUtils.showLoadingDialog(context: context, message: '更新中...');

        final updateResp =
            type == ImageSelectorType.poster
                ? await service.updateMoviePoster(movie.id, posterPath: url)
                : await service.updateMoviePoster(movie.id, backdropPath: url);

        if (context.mounted) {
          Navigator.pop(context);
        }
        if (!context.mounted) return;

        if (updateResp.isSuccess) {
          _invalidateMovieDetail();
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

  Future<void> _updateMovieScraping(BuildContext context, Movie movie) async {
    final storageId = movie.storageId;
    final path = _movieScrapePath(movie);
    if (storageId == null || path == null) {
      DialogUtils.showToast(
        context: context,
        message: '缺少存储路径，无法更新刮削',
        isError: true,
      );
      return;
    }

    final success = await DialogUtils.showCustomDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PathScanDialog(storageId: storageId, path: path),
    );

    if (!context.mounted) return;
    if (success == true) {
      _invalidateMovieDetail();
    }
  }

  String? _movieScrapePath(Movie movie) {
    final sourceFolders = movie.sourceFolders;
    if (sourceFolders != null) {
      for (final folder in sourceFolders) {
        final path = folder.trim();
        if (path.isNotEmpty) return path;
      }
    }
    return _movieDirectoryPath(movie);
  }

  String? _movieDirectoryPath(Movie movie) {
    final filePath = movie.filePath?.trim().replaceAll('\\', '/');
    if (filePath == null || filePath.isEmpty) return null;
    final index = filePath.lastIndexOf('/');
    if (index < 0) return null;
    if (index == 0) return filePath.substring(0, 1);
    return filePath.substring(0, index);
  }

  /// 构建文件信息区
  Widget _buildFileInfoSection(
    BuildContext context,
    ThemeData theme,
    Movie movie,
  ) {
    final colors = context.appColors;
    // 从路径中提取文件名
    String? fileName;
    String? dirPath;
    if (movie.filePath != null && movie.filePath!.isNotEmpty) {
      final lastSlash = movie.filePath!.lastIndexOf('/');
      if (lastSlash >= 0) {
        fileName = movie.filePath!.substring(lastSlash + 1);
        dirPath = movie.filePath!.substring(0, lastSlash);
      } else {
        fileName = movie.filePath;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 分割线
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Divider(
            color: colors.textPrimary.withValues(alpha: 0.1),
            height: 24,
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
                  color: colors.textPrimary.withValues(alpha: 0.7),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'TMDB ID: ${movie.tmdbId ?? "未知"} | IMDB: ${movie.imdbId ?? "未知"}',
                style: TextStyle(
                  color: colors.textPrimary.withValues(alpha: 0.5),
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              ),
              if (movie.genres != null && movie.genres!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '类型: ${movie.genres!.join(", ")}',
                    style: TextStyle(
                      color: colors.textPrimary.withValues(alpha: 0.5),
                      fontSize: 11,
                    ),
                  ),
                ),
              if (movie.storageName != null && movie.storageName!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '存储: ${movie.storageName}',
                    style: TextStyle(
                      color: colors.textPrimary.withValues(alpha: 0.5),
                      fontSize: 11,
                    ),
                  ),
                ),
              if (fileName != null && fileName.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '文件: $fileName',
                    style: TextStyle(
                      color: colors.textPrimary.withValues(alpha: 0.5),
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              if (dirPath != null && dirPath.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '路径: $dirPath',
                    style: TextStyle(
                      color: colors.textPrimary.withValues(alpha: 0.5),
                      fontSize: 11,
                      fontFamily: 'monospace',
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
