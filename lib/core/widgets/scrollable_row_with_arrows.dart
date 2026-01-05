import 'package:flutter/material.dart';
import '../window/window_controls.dart';

class ScrollableRowWithArrows extends StatefulWidget {
  final Widget child;
  final ScrollController controller;
  final Widget? title;
  final double itemWidth;
  final double itemSpacing;
  final double horizontalPadding;

  const ScrollableRowWithArrows({
    super.key,
    required this.child,
    required this.controller,
    this.title,
    required this.itemWidth,
    required this.itemSpacing,
    this.horizontalPadding = 12,
  });

  static bool get disableManualScroll => WindowControls.isDesktop;

  @override
  State<ScrollableRowWithArrows> createState() =>
      _ScrollableRowWithArrowsState();
}

class _ScrollableRowWithArrowsState extends State<ScrollableRowWithArrows> {
  bool _canScrollLeft = false;
  bool _canScrollRight = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_updateScrollState);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateScrollState());
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
    final availableWidth = viewportWidth - widget.horizontalPadding * 2;
    final itemCount = ((availableWidth + widget.itemSpacing) /
            (widget.itemWidth + widget.itemSpacing))
        .floor();
    // 滚动距离 = (itemCount - 1) 个卡片的宽度，让最后一个变成第一个
    final scrollDistance =
        (itemCount - 1) * (widget.itemWidth + widget.itemSpacing);
    final target =
        (pos.pixels + (forward ? scrollDistance : -scrollDistance))
            .clamp(pos.minScrollExtent, pos.maxScrollExtent);
    widget.controller.animateTo(
      target,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = WindowControls.isDesktop;
    final showArrows = isDesktop && (_canScrollLeft || _canScrollRight);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.title != null)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: widget.horizontalPadding),
            child: Row(
              children: [
                Expanded(child: widget.title!),
                if (showArrows) ...[
                  _ArrowButton(
                    icon: Icons.chevron_left,
                    onTap: _canScrollLeft ? () => _scroll(false) : null,
                    enabled: _canScrollLeft,
                  ),
                  const SizedBox(width: 4),
                  _ArrowButton(
                    icon: Icons.chevron_right,
                    onTap: _canScrollRight ? () => _scroll(true) : null,
                    enabled: _canScrollRight,
                  ),
                ],
              ],
            ),
          ),
        if (widget.title != null) const SizedBox(height: 16),
        widget.child,
      ],
    );
  }
}

class _ArrowButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool enabled;

  const _ArrowButton({
    required this.icon,
    required this.onTap,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
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
