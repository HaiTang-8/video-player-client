import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/widgets/app_back_button.dart';
import '../../core/widgets/cast_avatar.dart';
import '../../core/widgets/desktop_title_bar.dart';
import '../../core/window/window_controls.dart';
import '../../core/widgets/loading_widget.dart';
import '../../core/utils/image_proxy.dart';
import '../../data/models/models.dart';
import '../../providers/providers.dart';

/// 电影详情页面
class MovieDetailScreen extends ConsumerWidget {
  final int movieId;

  const MovieDetailScreen({super.key, required this.movieId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final movieAsync = ref.watch(movieDetailProvider(movieId));
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
                    () => DesktopTitleBar(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      // Desktop 端自绘标题栏：返回按钮使用“<”样式，并让标题紧跟图标靠左展示（不居中）。
                      centerTitle: false,
                      leading: AppBackButton(onPressed: () => context.pop()),
                      title: const Text('加载中...'),
                      actions: const [],
                    ),
                error:
                    (error, stack) => DesktopTitleBar(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      // Desktop 端自绘标题栏：返回按钮使用“<”样式，并让标题紧跟图标靠左展示（不居中）。
                      centerTitle: false,
                      leading: AppBackButton(onPressed: () => context.pop()),
                      title: const Text('电影详情'),
                      actions: [
                        IconButton(
                          icon: const Icon(Icons.refresh),
                          onPressed:
                              () =>
                                  ref.invalidate(movieDetailProvider(movieId)),
                        ),
                      ],
                    ),
                data:
                    (movie) => DesktopTitleBar(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      // Desktop 端自绘标题栏：返回按钮使用“<”样式，并让“资源名称”紧跟图标靠左展示（不居中）。
                      centerTitle: false,
                      leading: AppBackButton(onPressed: () => context.pop()),
                      title: Text(movie?.title ?? '电影详情'),
                      actions: [
                        if (movie != null)
                          IconButton(
                            tooltip: '重新刮削',
                            icon: const Icon(Icons.auto_fix_high),
                            onPressed:
                                () => _scrapeMovie(context, ref, movie.id),
                          ),
                        IconButton(
                          icon: const Icon(Icons.refresh),
                          onPressed:
                              () =>
                                  ref.invalidate(movieDetailProvider(movieId)),
                        ),
                      ],
                    ),
              )
              : null,
      body: movieAsync.when(
        loading: () => const LoadingWidget(message: '加载中...'),
        error:
            (error, stack) => AppErrorWidget(
              message: error.toString(),
              onRetry: () => ref.invalidate(movieDetailProvider(movieId)),
            ),
        data: (movie) {
          if (movie == null) {
            return const AppErrorWidget(message: '电影不存在');
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

          return CustomScrollView(
            slivers: [
              // 顶部导航栏
              if (!isDesktop) _buildAppBar(context, ref, movie),

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
                  Colors.transparent,
                  Colors.white.withValues(alpha: 0.3),
                  Colors.white.withValues(alpha: 0.7),
                  Colors.white.withValues(alpha: 0.95),
                ],
                stops: const [0.0, 0.3, 0.6, 1.0],
              ),
            ),
          ),
        ),

        // Hero 内容（叠加在渐变蒙版上）
        Positioned(
          left: 24,
          right: 24,
          bottom: 24,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // 第一行：电影标题
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

              // 第二行：左侧播放按钮 + 右侧（元数据+简介）
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 左侧 - 播放按钮
                  _buildPlayButton(context),
                  const SizedBox(width: 24),

                  // 右侧 - 元数据 + 简介
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 元数据行
                        _buildMetadataRow(movie, forOverlay: false),
                        if (movie.overview != null && movie.overview!.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          // 简介
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
          ),
        ),
      ],
    );
  }

  /// 构建顶部导航栏
  Widget _buildAppBar(BuildContext context, WidgetRef ref, Movie movie) {
    return SliverAppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      pinned: true,
      toolbarHeight: 44,
      // 移动端顶部导航：返回按钮使用“<”样式，标题靠左（避免 iOS 默认居中）。
      centerTitle: false,
      automaticallyImplyLeading: false,
      leadingWidth: kAppBackButtonWidth,
      titleSpacing: 1,
      leading: AppBackButton(
        onPressed: () => context.pop(),
        color: Colors.black,
      ),
      title: Text(
        movie.title,
        style: const TextStyle(
          color: Colors.black,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.auto_fix_high, color: Colors.black, size: 20),
          onPressed: () => _scrapeMovie(context, ref, movie.id),
        ),
        IconButton(
          icon: const Icon(Icons.refresh, color: Colors.black, size: 20),
          onPressed: () => ref.invalidate(movieDetailProvider(movieId)),
        ),
      ],
    );
  }

  /// 构建播放按钮
  Widget _buildPlayButton(BuildContext context) {
    return Material(
      color: Colors.black,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: () => context.push('/player/movie/$movieId'),
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

    // 年份
    if (movie.year != null) {
      items.add(_buildMetadataItem('${movie.year}', null, forOverlay: forOverlay));
    }

    // 时长
    if (movie.runtime != null) {
      items.add(_buildMetadataItem(movie.formattedRuntime, null, forOverlay: forOverlay));
    }

    // 文件大小
    if (movie.fileSize != null) {
      items.add(_buildMetadataItem(movie.formattedFileSize, null, forOverlay: forOverlay));
    }

    return Wrap(spacing: 16, runSpacing: 8, children: items);
  }

  Widget _buildMetadataItem(String text, Color? color, {bool forOverlay = false}) {
    final defaultColor = forOverlay
        ? Colors.white.withValues(alpha: 0.85)
        : Colors.black.withValues(alpha: 0.7);
    return Text(
      text,
      style: TextStyle(
        color: color ?? defaultColor,
        fontSize: 14,
        fontWeight: color != null ? FontWeight.bold : FontWeight.normal,
        shadows: forOverlay
            ? const [
                Shadow(offset: Offset(0, 1), blurRadius: 2, color: Colors.black45),
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
            padding: EdgeInsets.symmetric(horizontal: 24),
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
              padding: const EdgeInsets.symmetric(horizontal: 24),
              scrollDirection: Axis.horizontal,
              itemCount: cast.length,
              separatorBuilder: (_, __) => const SizedBox(width: 20),
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

  Future<void> _scrapeMovie(BuildContext context, WidgetRef ref, int id) async {
    final service = ref.read(mediaServiceProvider);
    if (service == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('未连接到服务器')));
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('重新刮削'),
            content: const Text('将从刮削源重新拉取元数据（海报、简介、演员表等）。是否继续？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('开始'),
              ),
            ],
          ),
    );

    if (confirmed != true || !context.mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder:
          (_) => const AlertDialog(
            content: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 12),
                Text('正在刮削...'),
              ],
            ),
          ),
    );

    final resp = await service.scrapeMovie(id);

    if (context.mounted) {
      Navigator.pop(context);
    }
    if (!context.mounted) return;

    if (resp.isSuccess) {
      ref.invalidate(movieDetailProvider(id));
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('刮削完成')));
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(resp.error ?? '刮削失败')));
  }

  /// 构建文件信息区
  Widget _buildFileInfoSection(
    BuildContext context,
    ThemeData theme,
    Movie movie,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 分割线
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Divider(
            color: Colors.black.withValues(alpha: 0.1),
            height: 48,
          ),
        ),

        // 文件信息
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
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
            ],
          ),
        ),
      ],
    );
  }
}
