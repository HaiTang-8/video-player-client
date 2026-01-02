import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pull_down_button/pull_down_button.dart';
import '../../core/widgets/app_back_button.dart';
import '../../core/widgets/cast_avatar.dart';
import '../../core/widgets/desktop_app_bar.dart';
import '../../core/widgets/image_selector_sheet.dart';
import '../../core/widgets/ios_ui_utils.dart';
import '../../core/window/window_controls.dart';
import '../../core/widgets/loading_widget.dart';
import '../../core/widgets/overview_preview_text.dart';
import '../../core/utils/image_proxy.dart';
import '../../data/models/models.dart';
import '../../providers/providers.dart';

/// 电影详情页面
class MovieDetailScreen extends ConsumerStatefulWidget {
  final int movieId;

  const MovieDetailScreen({super.key, required this.movieId});

  @override
  ConsumerState<MovieDetailScreen> createState() => _MovieDetailScreenState();
}

class _MovieDetailScreenState extends ConsumerState<MovieDetailScreen> {
  Movie? _movie;

  @override
  Widget build(BuildContext context) {
    final movieAsync = ref.watch(movieDetailProvider(widget.movieId));
    final theme = Theme.of(context);
    final screenSize = MediaQuery.of(context).size;
    final isDesktop = WindowControls.isDesktop;
    final serverBaseUrl = ref.watch(serverUrlProvider);

    return Scaffold(
      backgroundColor: Colors.white,
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
        loading: () => const LoadingWidget(message: '加载中...'),
        error:
            (error, stack) => AppErrorWidget(
              message: error.toString(),
              onRetry:
                  () => ref.invalidate(movieDetailProvider(widget.movieId)),
            ),
        data: (movie) {
          if (movie == null) {
            return const AppErrorWidget(message: '电影不存在');
          }
          _movie = movie;

          final cast =
              (movie.castDetail != null && movie.castDetail!.isNotEmpty)
                  ? movie.castDetail!
                  : (movie.cast != null
                      ? movie.cast!
                          .where((e) => e.trim().isNotEmpty)
                          .map((e) => CastMember(name: e.trim()))
                          .toList()
                      : const <CastMember>[]);

          return CustomScrollView(
            slivers: [
              // 顶部导航栏
              if (!isDesktop) _buildAppBar(context, movie),

              // 背景图区域（含渐变蒙版和 Hero 内容）
              SliverToBoxAdapter(
                child: _buildBackgroundWithHero(
                  context,
                  movie,
                  screenSize,
                  serverBaseUrl,
                  isDesktop: isDesktop,
                ),
              ),

              // 剧情简介（移动端）
              if (!isDesktop &&
                  movie.overview != null &&
                  movie.overview!.isNotEmpty)
                SliverToBoxAdapter(child: _buildOverviewSection(movie)),

              // 相关演员区（优先使用 cast_detail 以展示头像/角色；没有则回退 cast 姓名列表）
              if (cast.isNotEmpty)
                SliverToBoxAdapter(
                  child: _buildCastSection(context, theme, cast, serverBaseUrl),
                ),

              // 文件信息区
              SliverToBoxAdapter(
                child: _buildFileInfoSection(context, theme, movie),
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
                  ? _buildDesktopHeroContent(context, movie)
                  : _buildMobileHeroContent(context, movie),
        ),
      ],
    );
  }

  Widget _buildDesktopHeroContent(BuildContext context, Movie movie) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          movie.title,
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
                  _buildMetadataRow(movie, forOverlay: false),
                  if (movie.overview != null && movie.overview!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      movie.overview!,
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

  Widget _buildMobileHeroContent(BuildContext context, Movie movie) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 第一行：标题
        Text(
          movie.title,
          style: const TextStyle(
            color: Colors.black,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        // 第二行：评分 | 发布时间 | 时长
        _buildMobileMetadataRow1(movie),
        const SizedBox(height: 6),
        // 第三行：类型 | 文件大小
        _buildMobileMetadataRow2(movie),
        const SizedBox(height: 12),
        // 第四行：播放按钮
        _buildFullWidthPlayButton(context),
      ],
    );
  }

  Widget _buildMobileMetadataRow1(Movie movie) {
    final items = <Widget>[];
    final textStyle = TextStyle(
      color: Colors.black.withValues(alpha: 0.7),
      fontSize: 13,
    );
    final iconColor = Colors.black.withValues(alpha: 0.5);

    // 评分
    if (movie.rating != null && movie.rating! > 0) {
      items.add(
        Text(
          '豆 ${movie.rating!.toStringAsFixed(1)}',
          style: const TextStyle(
            color: Colors.green,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }

    // 发布时间
    if (movie.releaseDate != null || movie.year != null) {
      if (items.isNotEmpty) items.add(_buildDivider());
      final dateText =
          movie.releaseDate != null
              ? '${movie.releaseDate!.year}-${movie.releaseDate!.month.toString().padLeft(2, '0')}-${movie.releaseDate!.day.toString().padLeft(2, '0')}'
              : '${movie.year}';
      items.add(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.calendar_today, size: 14, color: iconColor),
            const SizedBox(width: 4),
            Text(dateText, style: textStyle),
          ],
        ),
      );
    }

    // 时长
    if (movie.runtime != null) {
      if (items.isNotEmpty) items.add(_buildDivider());
      items.add(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.access_time, size: 14, color: iconColor),
            const SizedBox(width: 4),
            Text(movie.formattedRuntime, style: textStyle),
          ],
        ),
      );
    }

    return Wrap(spacing: 0, runSpacing: 6, children: items);
  }

  Widget _buildMobileMetadataRow2(Movie movie) {
    final items = <Widget>[];
    final textStyle = TextStyle(
      color: Colors.black.withValues(alpha: 0.7),
      fontSize: 13,
    );

    // 类型
    if (movie.genres != null && movie.genres!.isNotEmpty) {
      items.add(Text(movie.genres!.join(' / '), style: textStyle));
    }

    // 文件大小
    if (movie.fileSize != null) {
      if (items.isNotEmpty) items.add(_buildDivider());
      items.add(Text(movie.formattedFileSize, style: textStyle));
    }

    return Wrap(spacing: 0, runSpacing: 6, children: items);
  }

  Widget _buildDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        '|',
        style: TextStyle(
          color: Colors.black.withValues(alpha: 0.3),
          fontSize: 13,
        ),
      ),
    );
  }

  Widget _buildFullWidthPlayButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: Colors.black,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: () => _playMovie(context),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.play_arrow, color: Colors.white, size: 24),
                SizedBox(width: 8),
                Text(
                  '播放',
                  style: TextStyle(
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

  Widget _buildOverviewSection(Movie movie) {
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
            title: movie.title,
            overview: movie.overview!,
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
  Widget _buildAppBar(BuildContext context, Movie movie) {
    final hasFile = movie.filePath != null && movie.filePath!.isNotEmpty;

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
      title: Text(movie.title),
      actions: [
        if (hasFile)
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            onPressed: () => _downloadMovie(context, movie),
            child: const Icon(CupertinoIcons.cloud_download, color: Colors.black, size: 22),
          ),
        PullDownButton(
          itemBuilder: (context) => [
            PullDownMenuItem(
              title: '更换海报',
              icon: CupertinoIcons.photo,
              onTap: () => _showImageSelector(context, movie, ImageSelectorType.poster),
            ),
            PullDownMenuItem(
              title: '更换背景图',
              icon: CupertinoIcons.photo_on_rectangle,
              onTap: () => _showImageSelector(context, movie, ImageSelectorType.backdrop),
            ),
            const PullDownMenuDivider(),
            PullDownMenuItem(
              title: '重新刮削',
              icon: CupertinoIcons.wand_stars,
              onTap: () => _scrapeMovie(context, movie.id),
            ),
            PullDownMenuItem(
              title: '刷新',
              icon: CupertinoIcons.refresh,
              onTap: () => ref.invalidate(movieDetailProvider(widget.movieId)),
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

  Future<void> _downloadMovie(BuildContext context, Movie movie) async {
    final downloadManager = ref.read(downloadManagerProvider.notifier);
    downloadManager.addMovieDownload(movie: movie);
    IosUiUtils.showToast(context: context, message: '已添加到下载队列');
  }

  List<Widget> _buildDesktopActions(Movie? movie) {
    if (movie == null) return [];
    final hasFile = movie.filePath != null && movie.filePath!.isNotEmpty;
    return [
      if (hasFile)
        IconButton(
          tooltip: '下载',
          icon: const Icon(CupertinoIcons.cloud_download),
          onPressed: () => _downloadMovie(context, movie),
        ),
      PullDownButton(
        itemBuilder: (context) => [
          PullDownMenuItem(
            title: '更换海报',
            icon: CupertinoIcons.photo,
            onTap: () => _showImageSelector(context, movie, ImageSelectorType.poster),
          ),
          PullDownMenuItem(
            title: '更换背景图',
            icon: CupertinoIcons.photo_on_rectangle,
            onTap: () => _showImageSelector(context, movie, ImageSelectorType.backdrop),
          ),
          const PullDownMenuDivider(),
          PullDownMenuItem(
            title: '重新刮削',
            icon: CupertinoIcons.wand_stars,
            onTap: () => _scrapeMovie(context, movie.id),
          ),
          PullDownMenuItem(
            title: '刷新',
            icon: CupertinoIcons.refresh,
            onTap: () => ref.invalidate(movieDetailProvider(widget.movieId)),
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
    return Material(
      color: Colors.black,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: () => _playMovie(context),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.play_arrow, color: Colors.white, size: 24),
              SizedBox(width: 8),
              Text(
                '播放',
                style: TextStyle(
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

  Future<void> _playMovie(BuildContext context) async {
    final movie = _movie;
    if (movie == null) return;

    final service = ref.read(mediaServiceProvider);
    int? position;

    if (service != null) {
      final historyResp = await service.getWatchProgress('movie', movie.id);
      debugPrint(
        '[_playMovie] historyResp.isSuccess=${historyResp.isSuccess}, data=${historyResp.data}, error=${historyResp.error}',
      );
      if (historyResp.isSuccess && historyResp.data != null) {
        debugPrint(
          '[_playMovie] position=${historyResp.data!.position}, completed=${historyResp.data!.completed}',
        );
        if (!historyResp.data!.completed) {
          position = historyResp.data!.position;
        }
      }
    }

    debugPrint('[_playMovie] final position=$position, title=${movie.title}');
    if (!context.mounted) return;
    debugPrint('[_playMovie] before push');
    await context.push(
      '/player/movie/${movie.id}',
      extra: {'position': position, 'title': movie.title},
    );
    debugPrint('[_playMovie] after push, waiting 500ms');
    await Future.delayed(const Duration(milliseconds: 500));
    debugPrint('[_playMovie] calling refresh');
    ref.read(watchHistoryProvider.notifier).refresh();
  }

  /// 构建元数据行
  Widget _buildMetadataRow(Movie movie, {bool forOverlay = false}) {
    final items = <Widget>[];

    // 评分
    if (movie.rating != null && movie.rating! > 0) {
      items.add(
        _buildMetadataItem(
          '豆 ${movie.rating!.toStringAsFixed(1)}',
          Colors.green,
          forOverlay: forOverlay,
        ),
      );
    }

    // 发布时间
    if (movie.releaseDate != null) {
      final dateText =
          '${movie.releaseDate!.year}-${movie.releaseDate!.month.toString().padLeft(2, '0')}-${movie.releaseDate!.day.toString().padLeft(2, '0')}';
      items.add(_buildMetadataItem(dateText, null, forOverlay: forOverlay));
    } else if (movie.year != null) {
      items.add(
        _buildMetadataItem('${movie.year}', null, forOverlay: forOverlay),
      );
    }

    // 时长
    if (movie.runtime != null) {
      items.add(
        _buildMetadataItem(
          movie.formattedRuntime,
          null,
          forOverlay: forOverlay,
        ),
      );
    }

    // 文件大小
    if (movie.fileSize != null) {
      items.add(
        _buildMetadataItem(
          movie.formattedFileSize,
          null,
          forOverlay: forOverlay,
        ),
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

  /// 构建相关演员区
  Widget _buildCastSection(
    BuildContext context,
    ThemeData theme,
    List<CastMember> cast,
    String? serverBaseUrl,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 区域标题
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              '相关演员',
              style: TextStyle(
                color: Colors.black,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 演员头像列表
          SizedBox(
            height: 120,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              scrollDirection: Axis.horizontal,
              itemCount: cast.length,
              separatorBuilder: (_, __) => const SizedBox(width: 4),
              itemBuilder: (context, index) {
                return _buildCastCard(cast[index], serverBaseUrl);
              },
            ),
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
    Movie movie,
    ImageSelectorType type,
  ) async {
    final service = ref.read(mediaServiceProvider);
    final serverBaseUrl = ref.read(serverUrlProvider);
    if (service == null) {
      IosUiUtils.showToast(context: context, message: '未连接到服务器', isError: true);
      return;
    }

    if (movie.tmdbId == null) {
      IosUiUtils.showToast(context: context, message: '无 TMDB ID，无法获取图片', isError: true);
      return;
    }

    IosUiUtils.showLoadingDialog(context: context, message: '加载图片中...');

    final resp = await service.getMovieImages(movie.id);

    if (context.mounted) {
      Navigator.pop(context);
    }
    if (!context.mounted) return;

    if (!resp.isSuccess || resp.data == null) {
      IosUiUtils.showToast(
        context: context,
        message: resp.error ?? '获取图片失败',
        isError: true,
      );
      return;
    }

    final images = type == ImageSelectorType.poster
        ? resp.data!.posters
        : resp.data!.backdrops;
    final currentUrl = type == ImageSelectorType.poster
        ? movie.posterPath
        : movie.backdropPath;

    showImageSelector(
      context: context,
      images: images,
      type: type,
      currentUrl: currentUrl,
      serverBaseUrl: serverBaseUrl,
      onSelect: (url) async {
        IosUiUtils.showLoadingDialog(context: context, message: '更新中...');

        final updateResp = type == ImageSelectorType.poster
            ? await service.updateMoviePoster(movie.id, posterPath: url)
            : await service.updateMoviePoster(movie.id, backdropPath: url);

        if (context.mounted) {
          Navigator.pop(context);
        }
        if (!context.mounted) return;

        if (updateResp.isSuccess) {
          ref.invalidate(movieDetailProvider(widget.movieId));
          IosUiUtils.showToast(context: context, message: '更新成功');
        } else {
          IosUiUtils.showToast(
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
      IosUiUtils.showToast(context: context, message: '未连接到服务器', isError: true);
      return;
    }

    final confirmed = await IosUiUtils.showConfirmDialog(
      context: context,
      title: '重新刮削',
      content: '将从刮削源重新拉取元数据（海报、简介、演员表等）。是否继续？',
      confirmText: '开始',
    );

    if (confirmed != true || !context.mounted) return;

    IosUiUtils.showLoadingDialog(context: context, message: '正在刮削...');

    final resp = await service.scrapeMovie(id);

    if (context.mounted) {
      Navigator.pop(context);
    }
    if (!context.mounted) return;

    if (resp.isSuccess) {
      ref.invalidate(movieDetailProvider(id));
      IosUiUtils.showToast(context: context, message: '刮削完成');
      return;
    }

    IosUiUtils.showToast(
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
                'TMDB ID: ${movie.tmdbId ?? "未知"} | IMDB: ${movie.imdbId ?? "未知"}',
                style: TextStyle(
                  color: Colors.black.withValues(alpha: 0.3),
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
                      color: Colors.black.withValues(alpha: 0.3),
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
                      color: Colors.black.withValues(alpha: 0.3),
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
                      color: Colors.black.withValues(alpha: 0.3),
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
                      color: Colors.black.withValues(alpha: 0.3),
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
