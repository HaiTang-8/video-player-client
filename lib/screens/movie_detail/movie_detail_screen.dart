import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/widgets/app_back_button.dart';
import '../../core/widgets/desktop_title_bar.dart';
import '../../core/window/window_controls.dart';
import '../../core/widgets/loading_widget.dart';
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

    return Scaffold(
      backgroundColor: Colors.black,
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

          return CustomScrollView(
            slivers: [
              // 顶部导航栏
              if (!isDesktop) _buildAppBar(context, ref, movie),

              // 背景图区域
              SliverToBoxAdapter(
                child: _buildBackgroundImage(movie, screenSize),
              ),

              // Hero Section
              SliverToBoxAdapter(
                child: _buildHeroSection(context, theme, movie),
              ),

              // 相关演员区（占位）
              SliverToBoxAdapter(child: _buildCastSection(context, theme)),

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

  /// 构建背景图 - 清晰展示，底部渐变过渡
  Widget _buildBackgroundImage(Movie movie, Size screenSize) {
    final imagePath = movie.backdropPath ?? movie.posterPath;
    final imageHeight = screenSize.height * 0.7;

    return Stack(
      children: [
        // 背景图 - 清晰显示
        if (imagePath != null && imagePath.isNotEmpty)
          CachedNetworkImage(
            imageUrl: imagePath,
            width: double.infinity,
            height: imageHeight,
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
            errorWidget:
                (_, __, ___) =>
                    Container(height: imageHeight, color: Colors.black),
            placeholder:
                (_, __) => Container(height: imageHeight, color: Colors.black),
          )
        else
          Container(height: imageHeight, color: Colors.black),

        // 渐变蒙版 - 底部10%渐变到黑色
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: imageHeight * 0.1,
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black],
              ),
            ),
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
          icon: const Icon(Icons.refresh, color: Colors.black, size: 20),
          onPressed: () => ref.invalidate(movieDetailProvider(movieId)),
        ),
      ],
    );
  }

  /// 构建 Hero Section - 左右布局
  Widget _buildHeroSection(BuildContext context, ThemeData theme, Movie movie) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 左侧 - 标题和播放按钮
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 电影标题
                Text(
                  movie.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 24),

                // 播放按钮
                _buildPlayButton(context),
              ],
            ),
          ),

          const SizedBox(width: 32),

          // 右侧 - 元数据和简介
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 元数据行
                _buildMetadataRow(movie),
                const SizedBox(height: 16),

                // 剧情简介
                if (movie.overview != null && movie.overview!.isNotEmpty)
                  Text(
                    movie.overview!,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 14,
                      height: 1.6,
                    ),
                    maxLines: 5,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 构建播放按钮
  Widget _buildPlayButton(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: () => context.push('/player/movie/$movieId'),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.play_arrow, color: Colors.black, size: 24),
              SizedBox(width: 8),
              Text(
                '播放',
                style: TextStyle(
                  color: Colors.black,
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
  Widget _buildMetadataRow(Movie movie) {
    final items = <Widget>[];

    // 评分
    if (movie.rating != null && movie.rating! > 0) {
      items.add(
        _buildMetadataItem(
          '豆 ${movie.rating!.toStringAsFixed(1)}',
          Colors.green,
        ),
      );
    }

    // 年份
    if (movie.year != null) {
      items.add(_buildMetadataItem('${movie.year}', null));
    }

    // 时长
    if (movie.runtime != null) {
      items.add(_buildMetadataItem(movie.formattedRuntime, null));
    }

    // 文件大小
    if (movie.fileSize != null) {
      items.add(_buildMetadataItem(movie.formattedFileSize, null));
    }

    return Wrap(spacing: 16, runSpacing: 8, children: items);
  }

  Widget _buildMetadataItem(String text, Color? color) {
    return Text(
      text,
      style: TextStyle(
        color: color ?? Colors.white.withValues(alpha: 0.7),
        fontSize: 14,
        fontWeight: color != null ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }

  /// 构建相关演员区
  Widget _buildCastSection(BuildContext context, ThemeData theme) {
    // 模拟演员数据 - 实际项目中应从 API 获取
    final castMembers = <Map<String, String>>[
      {'name': '演员1', 'role': '角色1'},
      {'name': '演员2', 'role': '角色2'},
      {'name': '演员3', 'role': '角色3'},
      {'name': '演员4', 'role': '角色4'},
      {'name': '演员5', 'role': '角色5'},
    ];

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
                color: Colors.white,
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
              itemCount: castMembers.length,
              separatorBuilder: (_, __) => const SizedBox(width: 20),
              itemBuilder: (context, index) {
                final cast = castMembers[index];
                return _buildCastCard(cast['name']!, cast['role']!);
              },
            ),
          ),
        ],
      ),
    );
  }

  /// 构建演员卡片
  Widget _buildCastCard(String name, String role) {
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
              color: Colors.white.withValues(alpha: 0.1),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.2),
                width: 2,
              ),
            ),
            child: Icon(
              Icons.person,
              color: Colors.white.withValues(alpha: 0.5),
              size: 32,
            ),
          ),
          const SizedBox(height: 8),

          // 姓名
          Text(
            name,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),

          // 角色
          Text(
            '饰 $role',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
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
            color: Colors.white.withValues(alpha: 0.1),
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
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'TMDB ID: ${movie.tmdbId ?? "未知"} | IMDB: ${movie.imdbId ?? "未知"}',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.3),
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
                      color: Colors.white.withValues(alpha: 0.3),
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
