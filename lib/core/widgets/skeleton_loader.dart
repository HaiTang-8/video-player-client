import 'package:flutter/material.dart';

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
    _animation = Tween<double>(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
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

  const _SkeletonShimmerScope({
    required this.animation,
    required super.child,
  });

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

  const SkeletonBox({
    super.key,
    this.width,
    this.height,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final shimmer = SkeletonShimmer.maybeOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? const Color(0xFF2A2A2A) : const Color(0xFFE0E0E0);
    final highlightColor = isDark ? const Color(0xFF3A3A3A) : const Color(0xFFF5F5F5);
    final radius = borderRadius ?? BorderRadius.circular(8);

    if (shimmer == null) {
      // 没有 Shimmer 作用域时，使用静态灰块（性能与安全优先）。
      return Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          borderRadius: radius,
          color: baseColor,
        ),
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
