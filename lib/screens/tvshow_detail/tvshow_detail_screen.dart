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

  @override
  Widget build(BuildContext context) {
    final tvShowAsync = ref.watch(tvShowDetailProvider(widget.tvShowId));
    final theme = Theme.of(context);
    final screenSize = MediaQuery.of(context).size;
    final isDesktop = WindowControls.isDesktop;
    final serverBaseUrl = ref.watch(serverUrlProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar:
          isDesktop
              ? tvShowAsync.when(
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
                      title: const Text('剧集详情'),
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
                    (tvShow) => DesktopTitleBar(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      // Desktop 端自绘标题栏：返回按钮使用“<”样式，并让“资源名称”紧跟图标靠左展示（不居中）。
                      centerTitle: false,
                      leading: AppBackButton(onPressed: () => context.pop()),
                      title: Text(tvShow?.name ?? '剧集详情'),
                      actions: [
                        if (tvShow != null)
                          IconButton(
                            tooltip: '重新刮削',
                            icon: const Icon(Icons.auto_fix_high),
                            onPressed:
                                () => _scrapeTvShow(context, widget.tvShowId),
                          ),
                        IconButton(
                          icon: const Icon(Icons.refresh),
                          onPressed:
                              () => ref.invalidate(
                                tvShowDetailProvider(widget.tvShowId),
                              ),
                        ),
                      ],
                    ),
              )
              : null,
      body: tvShowAsync.when(
        loading: () => const LoadingWidget(message: '加载中...'),
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

          return CustomScrollView(
            slivers: [
              // 顶部导航栏
              if (!isDesktop) _buildAppBar(context, tvShow),

              // 背景图区域 - 作为滚动内容的一部分
              SliverToBoxAdapter(
                child: _buildBackgroundImage(tvShow, screenSize, serverBaseUrl),
              ),

              // Hero Section
              SliverToBoxAdapter(
                child: _buildHeroSection(
                  context,
                  theme,
                  tvShow,
                  selectedSeason,
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
                    serverBaseUrl: serverBaseUrl,
                  ),
                )
              else if (_selectedSeasonId != null)
                SliverToBoxAdapter(
                  child: _EpisodesCarousel(
                    tvShowId: widget.tvShowId,
                    seasonId: _selectedSeasonId!,
                  ),
                ),

              // 相关演员区
              if (cast.isNotEmpty)
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

  /// 构建背景图 - 清晰展示90%，底部渐变过渡
  Widget _buildBackgroundImage(
    TvShow tvShow,
    Size screenSize,
    String? serverBaseUrl,
  ) {
    final imagePath = tvShow.backdropPath ?? tvShow.posterPath;
    final imageHeight = screenSize.height * 0.7;
    final imageUrl =
        imagePath != null && imagePath.isNotEmpty
            ? ImageProxy.proxyTMDBIfNeeded(imagePath, serverBaseUrl)
            : null;

    return Stack(
      children: [
        // 背景图 - 清晰显示
        if (imageUrl != null && imageUrl.isNotEmpty)
          CachedNetworkImage(
            imageUrl: imageUrl,
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
          height: imageHeight * 0.1, // 只有底部10%有渐变
          child: Container(
            decoration: BoxDecoration(
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
  Widget _buildAppBar(BuildContext context, TvShow tvShow) {
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
        tvShow.name,
        style: const TextStyle(
          color: Colors.black,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.auto_fix_high, color: Colors.black, size: 20),
          onPressed: () => _scrapeTvShow(context, widget.tvShowId),
        ),
        IconButton(
          icon: const Icon(Icons.refresh, color: Colors.black, size: 20),
          onPressed:
              () => ref.invalidate(tvShowDetailProvider(widget.tvShowId)),
        ),
      ],
    );
  }

  /// 构建 Hero Section - 左右布局
  Widget _buildHeroSection(
    BuildContext context,
    ThemeData theme,
    TvShow tvShow,
    Season? selectedSeason,
  ) {
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
                // 季标题
                Text(
                  selectedSeason != null
                      ? '${tvShow.name} ${selectedSeason.displayName}'
                      : tvShow.name,
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
                _buildMetadataRow(tvShow, selectedSeason),
                const SizedBox(height: 16),

                // 剧情简介
                if (selectedSeason?.overview != null &&
                    selectedSeason!.overview!.isNotEmpty)
                  Text(
                    selectedSeason.overview!,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 14,
                      height: 1.6,
                    ),
                    maxLines: 5,
                    overflow: TextOverflow.ellipsis,
                  )
                else if (tvShow.overview != null && tvShow.overview!.isNotEmpty)
                  Text(
                    tvShow.overview!,
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
        onTap: () {
          // TODO: 播放第一集或继续播放
        },
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
  Widget _buildMetadataRow(TvShow tvShow, Season? selectedSeason) {
    final items = <Widget>[];

    // 评分
    if (tvShow.rating != null && tvShow.rating! > 0) {
      items.add(
        _buildMetadataItem(
          '豆 ${tvShow.rating!.toStringAsFixed(1)}',
          Colors.green,
        ),
      );
    }

    // 首播日期
    if (tvShow.firstAirDate != null) {
      items.add(
        _buildMetadataItem(
          '${tvShow.firstAirDate!.year}-${tvShow.firstAirDate!.month.toString().padLeft(2, '0')}-${tvShow.firstAirDate!.day.toString().padLeft(2, '0')}',
          null,
        ),
      );
    } else if (tvShow.year != null) {
      items.add(_buildMetadataItem('${tvShow.year}', null));
    }

    // 剧集数
    if (selectedSeason?.episodeCount != null) {
      items.add(_buildMetadataItem('共${selectedSeason!.episodeCount}集', null));
    } else if (tvShow.numberOfEpisodes != null) {
      items.add(_buildMetadataItem('共${tvShow.numberOfEpisodes}集', null));
    }

    // 状态
    if (tvShow.status != null) {
      items.add(_buildMetadataItem(tvShow.statusText, null));
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

  /// 构建剧集选择区 - 季度标签页
  Widget _buildEpisodeSelector(
    BuildContext context,
    ThemeData theme,
    TvShow tvShow,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 分季切换标签
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: tvShow.seasons!.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final season = tvShow.seasons![index];
                final isSelected = index == _selectedSeasonIndex;

                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedSeasonIndex = index;
                      _selectedSeasonId = season.id;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color:
                          isSelected
                              ? Colors.white.withValues(alpha: 0.15)
                              : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color:
                            isSelected
                                ? Colors.white.withValues(alpha: 0.3)
                                : Colors.white.withValues(alpha: 0.1),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          season.displayName,
                          style: TextStyle(
                            color:
                                isSelected
                                    ? Colors.white
                                    : Colors.white.withValues(alpha: 0.6),
                            fontSize: 14,
                            fontWeight:
                                isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                          ),
                        ),
                        if (isSelected) ...[
                          const SizedBox(width: 4),
                          Icon(
                            Icons.keyboard_arrow_down,
                            color: Colors.white.withValues(alpha: 0.8),
                            size: 18,
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
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
              color: Colors.white.withValues(alpha: 0.1),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.2),
                width: 2,
              ),
            ),
            child: ClipOval(
              child: CastAvatar(
                size: 64,
                imageUrl: profileUrl,
                serverBaseUrl: serverBaseUrl,
                iconColor: Colors.white.withValues(alpha: 0.5),
                iconSize: 32,
              ),
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

          // 角色信息（TMDB credits 可提供 character；其它来源可能为空）
          if (role != null && role.isNotEmpty)
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

  Future<void> _scrapeTvShow(BuildContext context, int id) async {
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

    final resp = await service.scrapeTvShow(id);

    if (context.mounted) {
      Navigator.pop(context);
    }
    if (!context.mounted) return;

    if (resp.isSuccess) {
      ref.invalidate(tvShowDetailProvider(id));
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
    TvShow tvShow,
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
                'TMDB ID: ${tvShow.tmdbId ?? "未知"} | IMDB: ${tvShow.imdbId ?? "未知"}',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.3),
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

/// 剧集水平滚动卡片列表 - 直接使用数据
class _EpisodesCarouselDirect extends StatelessWidget {
  final List<Episode> episodes;
  final int tvShowId;
  final int seasonId;
  final String? serverBaseUrl;

  const _EpisodesCarouselDirect({
    required this.episodes,
    required this.tvShowId,
    required this.seasonId,
    required this.serverBaseUrl,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 180,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        scrollDirection: Axis.horizontal,
        itemCount: episodes.length,
        separatorBuilder: (_, __) => const SizedBox(width: 16),
        itemBuilder: (context, index) {
          final episode = episodes[index];
          return _EpisodeCard(
            episode: episode,
            tvShowId: tvShowId,
            seasonId: seasonId,
            serverBaseUrl: serverBaseUrl,
          );
        },
      ),
    );
  }
}

/// 剧集水平滚动卡片列表
class _EpisodesCarousel extends ConsumerWidget {
  final int tvShowId;
  final int seasonId;

  const _EpisodesCarousel({required this.tvShowId, required this.seasonId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final serverBaseUrl = ref.watch(serverUrlProvider);
    final episodesAsync = ref.watch(
      seasonEpisodesProvider((tvShowId: tvShowId, seasonId: seasonId)),
    );

    return episodesAsync.when(
      loading:
          () => const SizedBox(
            height: 180,
            child: Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          ),
      error:
          (error, stack) => Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              '加载失败: $error',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
            ),
          ),
      data: (episodes) {
        if (episodes == null || episodes.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              '暂无剧集',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
            ),
          );
        }

        return SizedBox(
          height: 180,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            scrollDirection: Axis.horizontal,
            itemCount: episodes.length,
            separatorBuilder: (_, __) => const SizedBox(width: 16),
            itemBuilder: (context, index) {
              final episode = episodes[index];
              return _EpisodeCard(
                episode: episode,
                tvShowId: tvShowId,
                seasonId: seasonId,
                serverBaseUrl: serverBaseUrl,
              );
            },
          ),
        );
      },
    );
  }
}

/// 单集卡片 - 竖向布局
class _EpisodeCard extends StatelessWidget {
  final Episode episode;
  final int tvShowId;
  final int seasonId;
  final String? serverBaseUrl;

  const _EpisodeCard({
    required this.episode,
    required this.tvShowId,
    required this.seasonId,
    required this.serverBaseUrl,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap:
          episode.hasFile
              ? () => context.push(
                '/player/episode/$tvShowId/$seasonId/${episode.id}',
              )
              : null,
      child: SizedBox(
        width: 160,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 缩略图
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child:
                      episode.stillPath != null && episode.stillPath!.isNotEmpty
                          ? CachedNetworkImage(
                            imageUrl: ImageProxy.proxyTMDBIfNeeded(
                              episode.stillPath!,
                              serverBaseUrl,
                            ),
                            width: 160,
                            height: 90,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => _buildPlaceholder(),
                          )
                          : _buildPlaceholder(),
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
            const SizedBox(height: 10),

            // 标题
            Text(
              '${episode.episodeNumber}. ${episode.name ?? "第${episode.episodeNumber}集"}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      width: 160,
      height: 90,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        Icons.play_circle_outline,
        color: Colors.white.withValues(alpha: 0.3),
        size: 32,
      ),
    );
  }
}
