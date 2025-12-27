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
      backgroundColor: Colors.white,
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

          final seasonBackdrop = tvShow.backdrops != null && tvShow.backdrops!.isNotEmpty
              ? tvShow.backdrops![_selectedSeasonIndex % tvShow.backdrops!.length]
              : null;
          final episodeFallbackImage = seasonBackdrop ?? selectedSeason?.posterPath ?? tvShow.backdropPath ?? tvShow.posterPath;

          return CustomScrollView(
            slivers: [
              // 顶部导航栏
              if (!isDesktop) _buildAppBar(context, tvShow),

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
                  ),
                )
              else if (_selectedSeasonId != null)
                SliverToBoxAdapter(
                  child: _EpisodesCarousel(
                    tvShowId: widget.tvShowId,
                    seasonId: _selectedSeasonId!,
                    tvShowName: tvShow.name,
                    fallbackImageUrl: episodeFallbackImage,
                  ),
                ),

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
      final backdrops = tvShow.backdrops;
      if (backdrops != null && backdrops.isNotEmpty) {
        imagePathRaw = backdrops[_selectedSeasonIndex % backdrops.length];
      }
      imagePathRaw ??= tvShow.backdropPath;
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
          left: 24,
          right: 24,
          bottom: 24,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // 第一行：剧集标题（只有一季时不显示季度信息）
              Text(
                (tvShow.seasons != null && tvShow.seasons!.length > 1 && selectedSeason != null)
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
                        _buildMetadataRow(tvShow, selectedSeason, forOverlay: false),
                        // 简介
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

  /// 构建播放按钮
  Widget _buildPlayButton(BuildContext context) {
    return Material(
      color: Colors.black,
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
  Widget _buildMetadataRow(TvShow tvShow, Season? selectedSeason, {bool forOverlay = false}) {
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
      items.add(_buildMetadataItem('${tvShow.year}', null, forOverlay: forOverlay));
    }

    // 剧集数
    if (selectedSeason?.episodeCount != null) {
      items.add(_buildMetadataItem('共${selectedSeason!.episodeCount}集', null, forOverlay: forOverlay));
    } else if (tvShow.numberOfEpisodes != null) {
      items.add(_buildMetadataItem('共${tvShow.numberOfEpisodes}集', null, forOverlay: forOverlay));
    }

    // 状态
    if (tvShow.status != null) {
      items.add(_buildMetadataItem(tvShow.statusText, null, forOverlay: forOverlay));
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 区域标题
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              title,
              style: const TextStyle(
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 120,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              scrollDirection: Axis.horizontal,
              itemCount: crew.length,
              separatorBuilder: (_, __) => const SizedBox(width: 20),
              itemBuilder: (context, index) {
                return _buildCrewCard(crew[index], serverBaseUrl);
              },
            ),
          ),
        ],
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
  final String? tvShowName;
  final String? serverBaseUrl;
  final String? fallbackImageUrl;

  const _EpisodesCarouselDirect({
    required this.episodes,
    required this.tvShowId,
    required this.seasonId,
    this.tvShowName,
    required this.serverBaseUrl,
    this.fallbackImageUrl,
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
            tvShowName: tvShowName,
            serverBaseUrl: serverBaseUrl,
            fallbackImageUrl: fallbackImageUrl,
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
  final String? tvShowName;
  final String? fallbackImageUrl;

  const _EpisodesCarousel({
    required this.tvShowId,
    required this.seasonId,
    this.tvShowName,
    this.fallbackImageUrl,
  });

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
                tvShowName: tvShowName,
                serverBaseUrl: serverBaseUrl,
                fallbackImageUrl: fallbackImageUrl,
              );
            },
          ),
        );
      },
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

  const _EpisodeCard({
    required this.episode,
    required this.tvShowId,
    required this.seasonId,
    this.tvShowName,
    required this.serverBaseUrl,
    this.fallbackImageUrl,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap:
          episode.hasFile
              ? () => _playEpisode(context, ref)
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
                  child: _buildThumbnail(),
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
                color: Colors.black,
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

  Future<void> _playEpisode(BuildContext context, WidgetRef ref) async {
    final service = ref.read(mediaServiceProvider);
    int? position;

    if (service != null) {
      final historyResp = await service.getWatchProgress('tv', tvShowId);
      if (historyResp.isSuccess && historyResp.data != null &&
          historyResp.data!.episodeId == episode.id &&
          !historyResp.data!.completed) {
        position = historyResp.data!.position;
      }
    }

    if (!context.mounted) return;
    final title = tvShowName != null
        ? '$tvShowName - ${episode.displayTitle}'
        : episode.displayTitle;
    context.push(
      '/player/episode/$tvShowId/$seasonId/${episode.id}',
      extra: {'position': position, 'title': title},
    );
  }

  Widget _buildThumbnail() {
    final hasStill = episode.stillPath != null && episode.stillPath!.isNotEmpty;
    final imageUrl = hasStill ? episode.stillPath! : fallbackImageUrl;
    if (imageUrl != null && imageUrl.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: ImageProxy.proxyTMDBIfNeeded(imageUrl, serverBaseUrl),
        width: 160,
        height: 90,
        fit: BoxFit.cover,
        errorWidget: (_, __, ___) => _buildPlaceholder(),
      );
    }
    return _buildPlaceholder();
  }

  Widget _buildPlaceholder() {
    return Container(
      width: 160,
      height: 90,
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
          isSingleSeason ? '第一季' : season.displayName,
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

  void _showSourceGroupsDialog(BuildContext context, List<SourceGroup>? groups) {
    if (groups == null || groups.isEmpty) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => _SourceGroupsSheet(
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
              separatorBuilder: (_, __) => const Divider(height: 1, indent: 20, endIndent: 20),
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

  Future<void> _onSelectSource(BuildContext context, WidgetRef ref, SourceGroup group) async {
    if (group.isPrimary) {
      Navigator.pop(context);
      return;
    }

    final service = ref.read(mediaServiceProvider);
    if (service == null) return;

    Navigator.pop(context);

    final response = await service.setSeasonPrimarySource(tvShowId, seasonId, group.folderPath);
    if (response.isSuccess) {
      // 刷新播放源分组数据
      ref.invalidate(seasonSourceGroupsProvider((tvShowId: tvShowId, seasonId: seasonId)));
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
          fontWeight: group.isPrimary ? FontWeight.w600 : FontWeight.w500,
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
              Icon(Icons.video_file_outlined, size: 14, color: Colors.grey[600]),
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
      trailing: group.isPrimary
          ? const Icon(Icons.check_circle, color: Colors.blue)
          : const Icon(Icons.chevron_right, color: Colors.grey),
      onTap: onTap,
    );
  }
}
