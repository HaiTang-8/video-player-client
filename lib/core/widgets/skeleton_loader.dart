import 'package:flutter/material.dart';

import '../window/window_controls.dart';

export 'loading_widget.dart' show AppErrorWidget, EmptyWidget;

/// 骨架屏的 Shimmer 动画作用域。
///
/// 性能优化点：
/// - 旧实现：每个 [SkeletonBox] 都会创建一个 [AnimationController] 并 repeat()。
///   当列表/网格里同时存在大量骨架块时，会产生大量 ticker，CPU 开销显著，容易掉帧。
/// - 新实现：在列表/网格最外层放一个 [SkeletonShimmer]，所有 [SkeletonBox] 共享同一个
///   [AnimationController]，显著减少 ticker 数量与调度开销。
class SkeletonShimmer extends StatefulWidget {
  final Widget child;
  final Duration duration;

  const SkeletonShimmer({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 1200),
  });

  @override
  State<SkeletonShimmer> createState() => _SkeletonShimmerState();

  static Animation<double>? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_SkeletonShimmerScope>()
        ?.animation;
  }
}

class _SkeletonShimmerState extends State<SkeletonShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: widget.duration, vsync: this)
      ..repeat();
    // -1 -> 2 的区间方便在 stops 上做“扫光”效果：中间高亮从左外侧扫到右外侧。
    _animation = Tween<double>(
      begin: -1.0,
      end: 2.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _SkeletonShimmerScope(animation: _animation, child: widget.child);
  }
}

class _SkeletonShimmerScope extends InheritedWidget {
  final Animation<double> animation;

  const _SkeletonShimmerScope({required this.animation, required super.child});

  @override
  bool updateShouldNotify(_SkeletonShimmerScope oldWidget) {
    // animation 对象在本实现中是稳定的，避免不必要的依赖 rebuild。
    return animation != oldWidget.animation;
  }
}

/// 单个骨架块（矩形/圆角矩形）。
///
/// - 如果外层存在 [SkeletonShimmer]，则使用共享动画；
/// - 否则退化为静态占位（不做动画），避免意外创建额外的 controller。
class SkeletonBox extends StatelessWidget {
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;

  const SkeletonBox({super.key, this.width, this.height, this.borderRadius});

  @override
  Widget build(BuildContext context) {
    final shimmer = SkeletonShimmer.maybeOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor =
        isDark ? const Color(0xFF2A2A2A) : const Color(0xFFE0E0E0);
    final highlightColor =
        isDark ? const Color(0xFF3A3A3A) : const Color(0xFFF5F5F5);
    final radius = borderRadius ?? BorderRadius.circular(8);

    if (shimmer == null) {
      // 没有 Shimmer 作用域时，使用静态灰块（性能与安全优先）。
      return Container(
        width: width,
        height: height,
        decoration: BoxDecoration(borderRadius: radius, color: baseColor),
      );
    }

    // 这里使用 CustomPainter + repaint: shimmer：
    // - 动画 tick 只触发 repaint，不触发大量 widget rebuild；
    // - 多个 SkeletonBox 共享同一个 shimmer，提高整体性能。
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: _SkeletonBoxPainter(
          shimmer: shimmer,
          baseColor: baseColor,
          highlightColor: highlightColor,
          borderRadius: radius,
        ),
      ),
    );
  }
}

class _SkeletonBoxPainter extends CustomPainter {
  final Animation<double> shimmer;
  final Color baseColor;
  final Color highlightColor;
  final BorderRadius borderRadius;

  _SkeletonBoxPainter({
    required this.shimmer,
    required this.baseColor,
    required this.highlightColor,
    required this.borderRadius,
  }) : super(repaint: shimmer);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = borderRadius.toRRect(rect);

    final v = shimmer.value;
    final shader = LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [baseColor, highlightColor, baseColor],
      stops: [
        (v - 0.3).clamp(0.0, 1.0),
        v.clamp(0.0, 1.0),
        (v + 0.3).clamp(0.0, 1.0),
      ],
    ).createShader(rect);

    final paint = Paint()..shader = shader;
    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(covariant _SkeletonBoxPainter oldDelegate) {
    return oldDelegate.baseColor != baseColor ||
        oldDelegate.highlightColor != highlightColor ||
        oldDelegate.borderRadius != borderRadius;
  }
}

class PosterCardSkeleton extends StatelessWidget {
  final double width;

  const PosterCardSkeleton({super.key, this.width = 140});

  @override
  Widget build(BuildContext context) {
    final posterHeight = width * 1.5;

    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SkeletonBox(
            width: width,
            height: posterHeight,
            borderRadius: BorderRadius.circular(8),
          ),
          const SizedBox(height: 8),
          SkeletonBox(
            width: width * 0.8,
            height: 14,
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 4),
          SkeletonBox(
            width: width * 0.5,
            height: 12,
            borderRadius: BorderRadius.circular(4),
          ),
        ],
      ),
    );
  }
}

class GridSkeletonLoader extends StatelessWidget {
  final int itemCount;
  final double itemWidth;

  const GridSkeletonLoader({
    super.key,
    this.itemCount = 12,
    this.itemWidth = 140,
  });

  @override
  Widget build(BuildContext context) {
    return SkeletonShimmer(
      child: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 160,
          childAspectRatio: 0.48,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
        ),
        itemCount: itemCount,
        itemBuilder: (context, index) => PosterCardSkeleton(width: itemWidth),
      ),
    );
  }
}

class ListItemSkeleton extends StatelessWidget {
  const ListItemSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          SkeletonBox(
            width: 40,
            height: 40,
            borderRadius: BorderRadius.circular(8),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(
                  width: double.infinity,
                  height: 16,
                  borderRadius: BorderRadius.circular(4),
                ),
                const SizedBox(height: 6),
                SkeletonBox(
                  width: 100,
                  height: 12,
                  borderRadius: BorderRadius.circular(4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ListSkeletonLoader extends StatelessWidget {
  final int itemCount;

  const ListSkeletonLoader({super.key, this.itemCount = 10});

  @override
  Widget build(BuildContext context) {
    return SkeletonShimmer(
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: itemCount,
        itemBuilder: (context, index) => const ListItemSkeleton(),
      ),
    );
  }
}

/// 媒体库页面骨架屏 - 模拟分类横向滚动布局
class LibrarySkeletonLoader extends StatelessWidget {
  final int categoryCount;

  const LibrarySkeletonLoader({super.key, this.categoryCount = 3});

  @override
  Widget build(BuildContext context) {
    return SkeletonShimmer(
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 8, bottom: 16),
        itemCount: categoryCount,
        itemBuilder: (context, index) {
          if (index == 0) {
            return const _WatchHistoryRowSkeleton();
          }
          return const _CategoryRowSkeleton();
        },
      ),
    );
  }
}

class _SectionHeaderSkeleton extends StatelessWidget {
  final double titleWidth;

  const _SectionHeaderSkeleton({required this.titleWidth});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SkeletonBox(
            width: titleWidth,
            height: 20,
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(width: 8),
          SkeletonBox(
            width: 24,
            height: 16,
            borderRadius: BorderRadius.circular(4),
          ),
        ],
      ),
    );
  }
}

class _WatchHistoryRowSkeleton extends StatelessWidget {
  static const double _mobileItemWidth = 220.0;
  static const double _desktopMinItemWidth = 220.0;
  static const double _itemSpacing = 16.0;
  static const double _horizontalPadding = 16.0;

  const _WatchHistoryRowSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeaderSkeleton(titleWidth: 72),
        LayoutBuilder(
          builder: (context, constraints) {
            if (!WindowControls.isDesktop) {
              return _buildMobileContent(context, constraints.maxWidth);
            }
            return _buildDesktopContent(context, constraints.maxWidth);
          },
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildMobileContent(BuildContext context, double maxWidth) {
    final textScaler = MediaQuery.textScalerOf(context);
    final imageHeight = _mobileItemWidth * 9 / 16;
    final listHeight = imageHeight + 8 + textScaler.scale(60);
    final availableWidth = (maxWidth - _horizontalPadding * 2).clamp(
      _mobileItemWidth,
      double.infinity,
    );
    final itemCount =
        ((availableWidth + _itemSpacing) / (_mobileItemWidth + _itemSpacing))
            .floor();
    final visibleCount = itemCount > 0 ? itemCount : 1;

    return SizedBox(
      height: listHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: _horizontalPadding),
        itemCount: visibleCount,
        separatorBuilder: (_, _) => const SizedBox(width: _itemSpacing),
        itemBuilder:
            (_, _) => const _WatchHistoryCardSkeleton(width: _mobileItemWidth),
      ),
    );
  }

  Widget _buildDesktopContent(BuildContext context, double maxWidth) {
    final textScaler = MediaQuery.textScalerOf(context);
    final availableWidth = (maxWidth - _horizontalPadding * 2).clamp(
      _desktopMinItemWidth,
      double.infinity,
    );
    final rawCount =
        ((availableWidth + _itemSpacing) /
                (_desktopMinItemWidth + _itemSpacing))
            .floor();
    final itemCount = rawCount > 0 ? rawCount : 1;
    final itemWidth =
        (availableWidth - (itemCount - 1) * _itemSpacing) / itemCount;
    final textAreaHeight = textScaler.scale(40) + 2 + textScaler.scale(16);
    final listHeight = itemWidth * 9 / 16 + 8 + textAreaHeight;

    return SizedBox(
      height: listHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: _horizontalPadding),
        itemCount: itemCount,
        separatorBuilder: (_, _) => const SizedBox(width: _itemSpacing),
        itemBuilder: (_, _) => _WatchHistoryCardSkeleton(width: itemWidth),
      ),
    );
  }
}

class _CategoryRowSkeleton extends StatelessWidget {
  static const double _mobileItemWidth = 88.0;
  static const double _desktopItemWidth = 120.0;
  static const double _itemSpacing = 16.0;
  static const double _horizontalPadding = 16.0;

  const _CategoryRowSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeaderSkeleton(titleWidth: 80),
        LayoutBuilder(
          builder: (context, constraints) {
            if (!WindowControls.isDesktop) {
              return _buildMobileContent(context, constraints.maxWidth);
            }
            return _buildDesktopContent(context, constraints.maxWidth);
          },
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  Widget _buildMobileContent(BuildContext context, double maxWidth) {
    final textScaler = MediaQuery.textScalerOf(context);
    final listHeight = _mobileItemWidth * 1.5 + 8 + textScaler.scale(40);
    final availableWidth = (maxWidth - _horizontalPadding * 2).clamp(
      _mobileItemWidth,
      double.infinity,
    );
    final itemCount =
        ((availableWidth + _itemSpacing) / (_mobileItemWidth + _itemSpacing))
            .floor();
    final visibleCount = itemCount > 0 ? itemCount : 1;

    return SizedBox(
      height: listHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: _horizontalPadding),
        itemCount: visibleCount,
        separatorBuilder: (_, _) => const SizedBox(width: _itemSpacing),
        itemBuilder: (_, _) => const _PosterSkeleton(width: _mobileItemWidth),
      ),
    );
  }

  Widget _buildDesktopContent(BuildContext context, double maxWidth) {
    final availableWidth = (maxWidth - _horizontalPadding * 2).clamp(
      _desktopItemWidth,
      double.infinity,
    );
    final rawItemsPerRow =
        ((availableWidth + _itemSpacing) / (_desktopItemWidth + _itemSpacing))
            .floor();
    final itemsPerRow = rawItemsPerRow > 0 ? rawItemsPerRow : 1;
    final itemWidth =
        (availableWidth - (itemsPerRow - 1) * _itemSpacing) / itemsPerRow;
    final itemHeight = itemWidth / 0.48;
    final displayCount = itemsPerRow * 2;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _horizontalPadding),
      child: Wrap(
        spacing: _itemSpacing,
        runSpacing: _itemSpacing,
        children: List.generate(
          displayCount,
          (_) => SizedBox(
            width: itemWidth,
            height: itemHeight,
            child: _PosterSkeleton(width: itemWidth, height: itemHeight),
          ),
        ),
      ),
    );
  }
}

class _PosterSkeleton extends StatelessWidget {
  final double width;
  final double? height;

  const _PosterSkeleton({required this.width, this.height});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: height == null ? MainAxisSize.min : MainAxisSize.max,
        children: [
          SkeletonBox(
            width: width,
            height: width * 1.5,
            borderRadius: BorderRadius.circular(8),
          ),
          const SizedBox(height: 8),
          SkeletonBox(
            width: width * 0.8,
            height: 14,
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 4),
          SkeletonBox(
            width: width * 0.55,
            height: 12,
            borderRadius: BorderRadius.circular(4),
          ),
          if (height != null) const Spacer(),
        ],
      ),
    );
  }
}

class _WatchHistoryCardSkeleton extends StatelessWidget {
  final double width;

  const _WatchHistoryCardSkeleton({required this.width});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progressColor = theme.colorScheme.primary.withValues(alpha: 0.28);

    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Stack(
              children: [
                SkeletonBox(
                  width: width,
                  height: width * 9 / 16,
                  borderRadius: BorderRadius.circular(8),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(height: 4, color: progressColor),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SkeletonBox(
            width: width * 0.88,
            height: 14,
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 4),
          SkeletonBox(
            width: width * 0.38,
            height: 12,
            borderRadius: BorderRadius.circular(4),
          ),
        ],
      ),
    );
  }
}

/// 资源库页面骨架屏 - 模拟存储源列表
class StoragesSkeletonLoader extends StatelessWidget {
  final int itemCount;

  const StoragesSkeletonLoader({super.key, this.itemCount = 3});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return SkeletonShimmer(
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
            child: SkeletonBox(
              width: 50,
              height: 14,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: List.generate(
                itemCount,
                (index) =>
                    _StorageTileSkeleton(showDivider: index < itemCount - 1),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StorageTileSkeleton extends StatelessWidget {
  final bool showDivider;

  const _StorageTileSkeleton({this.showDivider = true});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              SkeletonBox(
                width: 36,
                height: 36,
                borderRadius: BorderRadius.circular(8),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBox(
                      width: 100,
                      height: 16,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    const SizedBox(height: 4),
                    SkeletonBox(
                      width: 160,
                      height: 12,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ],
                ),
              ),
              SkeletonBox(
                width: 20,
                height: 20,
                borderRadius: BorderRadius.circular(4),
              ),
            ],
          ),
        ),
        if (showDivider)
          Padding(
            padding: const EdgeInsets.only(left: 60),
            child: Divider(
              height: 1,
              thickness: 0.5,
              color: theme.dividerColor.withValues(alpha: 0.3),
            ),
          ),
      ],
    );
  }
}

/// 详情页骨架屏 - 模拟电影/剧集详情布局
class DetailSkeletonLoader extends StatelessWidget {
  const DetailSkeletonLoader({super.key});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final backdropHeight = size.height * 0.35;

    return SkeletonShimmer(
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonBox(
              width: double.infinity,
              height: backdropHeight,
              borderRadius: BorderRadius.zero,
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(
                    width: 200,
                    height: 24,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  const SizedBox(height: 8),
                  SkeletonBox(
                    width: 120,
                    height: 16,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  const SizedBox(height: 16),
                  SkeletonBox(
                    width: double.infinity,
                    height: 48,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  const SizedBox(height: 24),
                  SkeletonBox(
                    width: double.infinity,
                    height: 14,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  const SizedBox(height: 8),
                  SkeletonBox(
                    width: double.infinity,
                    height: 14,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  const SizedBox(height: 8),
                  SkeletonBox(
                    width: 200,
                    height: 14,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  const SizedBox(height: 24),
                  SkeletonBox(
                    width: 60,
                    height: 18,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 80,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: 6,
                      itemBuilder:
                          (context, index) => Padding(
                            padding: const EdgeInsets.only(right: 16),
                            child: Column(
                              children: [
                                SkeletonBox(
                                  width: 56,
                                  height: 56,
                                  borderRadius: BorderRadius.circular(28),
                                ),
                                const SizedBox(height: 6),
                                SkeletonBox(
                                  width: 50,
                                  height: 12,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ],
                            ),
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
