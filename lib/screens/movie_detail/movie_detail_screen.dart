import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;
import '../../core/theme/app_colors.dart';
import '../../core/theme/detail_background_palette.dart';
import '../../core/theme/app_theme.dart';
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
import '../../providers/providers.dart';

typedef _MovieHeroImage = ({double imageHeight, String? imageUrl});

/// 电影详情页面
class MovieDetailScreen extends ConsumerStatefulWidget {
  final int movieId;

  const MovieDetailScreen({super.key, required this.movieId});

  @override
  ConsumerState<MovieDetailScreen> createState() => _MovieDetailScreenState();
}

class _MovieDetailScreenState extends ConsumerState<MovieDetailScreen> {
  Movie? _movie;
  final _castScrollController = ScrollController();
  WatchHistoryItem? _watchHistory;
  bool _historyLoaded = false;
  bool _showSolidAppBar = false;
  Color? _mobileBackgroundColor;
  String? _mobileBackgroundImageUrl;

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
      setState(() => _watchHistory = resp.data);
    } else {
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

  Color _detailBackgroundColor(
    BuildContext context, {
    required String? imageUrl,
  }) {
    final fallbackColor = context.appColors.cardBackground;
    if (WindowControls.isDesktop ||
        imageUrl == null ||
        imageUrl.isEmpty ||
        _mobileBackgroundImageUrl != imageUrl) {
      return fallbackColor;
    }
    return _mobileBackgroundColor ?? fallbackColor;
  }

  void _resolveMobileBackgroundColor(
    String? imageUrl,
    String? accessToken, {
    required bool isDesktop,
  }) {
    if (isDesktop || imageUrl == null || imageUrl.isEmpty) {
      return;
    }
    if (_mobileBackgroundImageUrl == imageUrl) {
      return;
    }

    _mobileBackgroundImageUrl = imageUrl;
    _mobileBackgroundColor = DetailBackgroundPalette.getCached(imageUrl);
    final headers =
        accessToken != null
            ? <String, String>{'Authorization': 'Bearer $accessToken'}
            : null;

    DetailBackgroundPalette.resolve(
      imageUrl,
      provider: CachedNetworkImageProvider(imageUrl, headers: headers),
      fallbackColor: AppColors.dark.cardBackground,
    ).then((color) {
      if (!mounted || _mobileBackgroundImageUrl != imageUrl) {
        return;
      }
      if (_mobileBackgroundColor == color) {
        return;
      }
      setState(() {
        _mobileBackgroundColor = color;
      });
    });
  }

  _MovieHeroImage _resolveHeroImage(
    Movie movie,
    Size screenSize,
    String? serverBaseUrl, {
    required bool isDesktop,
  }) {
    String? imagePathRaw;
    bool usePoster = false;
    if (isDesktop) {
      imagePathRaw = movie.backdropPath;
      if (imagePathRaw == null || imagePathRaw.isEmpty) {
        imagePathRaw = movie.posterPath;
        usePoster = true;
      }
    } else {
      imagePathRaw = movie.posterPath;
      usePoster = true;
      if (imagePathRaw == null || imagePathRaw.isEmpty) {
        imagePathRaw = movie.backdropPath;
        usePoster = false;
      }
    }

    var imagePath = imagePathRaw;
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
            return screenSize.height * 0.75;
          }
          const backdropAspect = 16 / 9;
          final idealHeight = screenSize.width / backdropAspect;
          final minHeight = screenSize.height * 0.55;
          final maxHeight = screenSize.height * 0.9;
          return idealHeight.clamp(minHeight, maxHeight);
        })().ceilToDouble();

    final imageUrl =
        imagePath != null && imagePath.isNotEmpty
            ? ImageProxy.proxyTMDBIfNeeded(imagePath, serverBaseUrl)
            : null;

    return (imageHeight: imageHeight, imageUrl: imageUrl);
  }

  @override
  Widget build(BuildContext context) {
    final movieAsync = ref.watch(movieDetailProvider(widget.movieId));
    final baseTheme = Theme.of(context);
    final screenSize = MediaQuery.of(context).size;
    final isDesktop = WindowControls.isDesktop;
    final serverBaseUrl = ref.watch(serverUrlProvider);
    final accessToken = ref.watch(authProvider).tokens?.accessToken;

    return Theme(
      data: isDesktop ? baseTheme : AppTheme.mobileDetailDarkTheme(baseTheme),
      child: Builder(
        builder: (context) {
          final theme = Theme.of(context);

          return Scaffold(
            backgroundColor: _detailBackgroundColor(
              context,
              imageUrl: _mobileBackgroundImageUrl,
            ),
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
                                onPressed:
                                    () => ref.invalidate(
                                      movieDetailProvider(widget.movieId),
                                    ),
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
                    onRetry:
                        () =>
                            ref.invalidate(movieDetailProvider(widget.movieId)),
                  ),
              data: (movie) {
                if (movie == null) {
                  return const AppErrorWidget(message: '电影不存在');
                }
                _movie = movie;
                final heroImage = _resolveHeroImage(
                  movie,
                  screenSize,
                  serverBaseUrl,
                  isDesktop: isDesktop,
                );
                _resolveMobileBackgroundColor(
                  heroImage.imageUrl,
                  accessToken,
                  isDesktop: isDesktop,
                );
                final detailBackgroundColor = _detailBackgroundColor(
                  context,
                  imageUrl: heroImage.imageUrl,
                );
                if (!_historyLoaded) {
                  _historyLoaded = true;
                  _loadWatchHistory();
                }

                final cast =
                    (movie.castDetail != null && movie.castDetail!.isNotEmpty)
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
                        child: _buildBackgroundWithHero(
                          context,
                          movie,
                          heroImage,
                          accessToken,
                          backgroundColor: detailBackgroundColor,
                          isDesktop: true,
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
                        child: _buildFileInfoSection(context, theme, movie),
                      ),
                      const SliverToBoxAdapter(child: SizedBox(height: 32)),
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
                            child: _buildBackgroundWithHero(
                              context,
                              movie,
                              heroImage,
                              accessToken,
                              backgroundColor: detailBackgroundColor,
                              isDesktop: false,
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
                            child: _buildFileInfoSection(context, theme, movie),
                          ),
                          const SliverToBoxAdapter(child: SizedBox(height: 32)),
                        ],
                      ),
                    ),
                    _buildMobileAppBar(context, movie, solid: _showSolidAppBar),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }

  /// 构建背景图（含渐变蒙版和 Hero 内容）
  Widget _buildBackgroundWithHero(
    BuildContext context,
    Movie movie,
    _MovieHeroImage heroImage,
    String? accessToken, {
    required Color backgroundColor,
    required bool isDesktop,
  }) {
    final imageHeight = heroImage.imageHeight;
    final gradientHeight = (imageHeight * 0.5).ceilToDouble();
    final imageUrl = heroImage.imageUrl;

    return Stack(
      children: [
        // 背景图
        if (imageUrl != null && imageUrl.isNotEmpty)
          CachedNetworkImage(
            imageUrl: imageUrl,
            httpHeaders:
                accessToken != null
                    ? {'Authorization': 'Bearer $accessToken'}
                    : null,
            width: double.infinity,
            height: imageHeight,
            fit: isDesktop ? BoxFit.cover : BoxFit.fitWidth,
            alignment: Alignment.topCenter,
            errorWidget:
                (_, _, _) =>
                    Container(height: imageHeight, color: Colors.grey[300]),
            placeholder:
                (_, _) =>
                    Container(height: imageHeight, color: Colors.grey[300]),
          )
        else
          Container(height: imageHeight, color: Colors.grey[300]),

        // 渐变蒙版
        if (!isDesktop)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: MediaQuery.of(context).padding.top + 96,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.45),
                    Colors.black.withValues(alpha: 0.18),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
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
                  backgroundColor.withValues(alpha: 0.0),
                  backgroundColor.withValues(alpha: 0.2),
                  backgroundColor.withValues(alpha: 0.5),
                  backgroundColor.withValues(alpha: 0.8),
                  backgroundColor,
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
                  ? _buildDesktopHeroContent(context, movie)
                  : _buildMobileHeroContent(context, movie),
        ),
      ],
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
                  _buildMetadataRow(context, movie, forOverlay: false),
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
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        _buildMobileMetadataRow1(context, movie),
        const SizedBox(height: 6),
        _buildMobileMetadataRow2(context, movie),
        const SizedBox(height: 20),
        _buildFullWidthPlayButton(context),
      ],
    );
  }

  Widget _buildMobileMetadataRow1(BuildContext context, Movie movie) {
    final colors = context.appColors;
    final items = <Widget>[];
    final textStyle = TextStyle(
      color: colors.textPrimary.withValues(alpha: 0.7),
      fontSize: 14,
      fontWeight: FontWeight.bold,
    );
    final iconColor = colors.textPrimary.withValues(alpha: 0.5);

    if (movie.rating != null && movie.rating! > 0) {
      items.add(
        Text(
          'TMDB ${movie.rating!.toStringAsFixed(1)}',
          style: const TextStyle(
            color: Colors.green,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
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

  Widget _buildMobileMetadataRow2(BuildContext context, Movie movie) {
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

  Widget _buildFullWidthPlayButton(BuildContext context) {
    final colors = context.appColors;
    final buttonBackground = colors.textPrimary;
    final buttonForeground = _detailBackgroundColor(
      context,
      imageUrl: _mobileBackgroundImageUrl,
    );
    final history = _watchHistory;
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
    final backgroundColor = _detailBackgroundColor(
      context,
      imageUrl: _mobileBackgroundImageUrl,
    );

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
                leading: const Icon(CupertinoIcons.wand_stars, size: 18),
                child: const Text('重新刮削'),
                onPressed: (menuContext) {
                  shadcn.closeOverlay(menuContext);
                  _scrapeMovie(context, movie.id);
                },
              ),
              shadcn.MenuButton(
                leading: const Icon(CupertinoIcons.refresh, size: 18),
                child: const Text('刷新'),
                onPressed: (menuContext) {
                  shadcn.closeOverlay(menuContext);
                  ref.invalidate(movieDetailProvider(widget.movieId));
                },
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
                leading: const Icon(CupertinoIcons.wand_stars, size: 18),
                child: const Text('重新刮削'),
                onPressed: (menuContext) {
                  shadcn.closeOverlay(menuContext);
                  _scrapeMovie(context, movie.id);
                },
              ),
              shadcn.MenuButton(
                leading: const Icon(CupertinoIcons.refresh, size: 18),
                child: const Text('刷新'),
                onPressed: (menuContext) {
                  shadcn.closeOverlay(menuContext);
                  ref.invalidate(movieDetailProvider(widget.movieId));
                },
              ),
            ],
          ),
        );
      },
    );
  }

  /// 构建播放按钮
  Widget _buildPlayButton(BuildContext context) {
    final colors = context.appColors;
    final buttonBackground = colors.textPrimary;
    final buttonForeground = _detailBackgroundColor(
      context,
      imageUrl: _mobileBackgroundImageUrl,
    );
    final history = _watchHistory;
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

  /// 构建元数据行
  Widget _buildMetadataRow(
    BuildContext context,
    Movie movie, {
    bool forOverlay = false,
  }) {
    final items = <Widget>[];

    if (movie.rating != null && movie.rating! > 0) {
      items.add(
        _buildMetadataItem(
          context,
          '豆 ${movie.rating!.toStringAsFixed(1)}',
          Colors.green,
          forOverlay: forOverlay,
        ),
      );
    }

    if (movie.releaseDate != null) {
      final dateText =
          '${movie.releaseDate!.year}-${movie.releaseDate!.month.toString().padLeft(2, '0')}-${movie.releaseDate!.day.toString().padLeft(2, '0')}';
      items.add(
        _buildMetadataItem(context, dateText, null, forOverlay: forOverlay),
      );
    } else if (movie.year != null) {
      items.add(
        _buildMetadataItem(
          context,
          '${movie.year}',
          null,
          forOverlay: forOverlay,
        ),
      );
    }

    if (movie.runtime != null) {
      items.add(
        _buildMetadataItem(
          context,
          movie.formattedRuntime,
          null,
          forOverlay: forOverlay,
        ),
      );
    }

    if (movie.fileSize != null) {
      items.add(
        _buildMetadataItem(
          context,
          movie.formattedFileSize,
          null,
          forOverlay: forOverlay,
        ),
      );
    }

    return Wrap(spacing: 16, runSpacing: 8, children: items);
  }

  Widget _buildMetadataItem(
    BuildContext context,
    String text,
    Color? color, {
    bool forOverlay = false,
  }) {
    final colors = context.appColors;
    final defaultColor =
        forOverlay
            ? Colors.white.withValues(alpha: 0.85)
            : colors.textPrimary.withValues(alpha: 0.7);
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
          ref.invalidate(movieDetailProvider(widget.movieId));
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

  Future<void> _scrapeMovie(BuildContext context, int id) async {
    final service = ref.read(mediaServiceProvider);
    if (service == null) {
      DialogUtils.showToast(
        context: context,
        message: '未连接到服务器',
        isError: true,
      );
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

    final resp = await service.scrapeMovie(id);

    if (context.mounted) {
      Navigator.pop(context);
    }
    if (!context.mounted) return;

    if (resp.isSuccess) {
      ref.invalidate(movieDetailProvider(id));
      DialogUtils.showToast(context: context, message: '刮削完成');
      return;
    }

    DialogUtils.showToast(
      context: context,
      message: resp.error ?? '刮削失败',
      isError: true,
    );
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
