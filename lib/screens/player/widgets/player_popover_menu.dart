import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' show LucideIcons;

import '../../../core/window/window_controls.dart';

class PlayerMenuItem {
  final String label;
  final IconData? icon;
  final bool? selected;
  final VoidCallback? onSelected;
  final FutureOr<void> Function()? onAction;

  /// 单选项：点击后立即生效，勾选移到该项后菜单关闭
  const PlayerMenuItem.option(
    this.label, {
    required bool this.selected,
    required VoidCallback this.onSelected,
  }) : icon = null,
       onAction = null;

  /// 操作项：菜单关闭后再执行
  const PlayerMenuItem.action(
    this.label, {
    this.icon,
    required FutureOr<void> Function() this.onAction,
  }) : selected = null,
       onSelected = null;

  const PlayerMenuItem.disabled(this.label)
    : icon = null,
      selected = null,
      onSelected = null,
      onAction = null;

  bool get enabled => onSelected != null || onAction != null;
}

/// 播放器内从触发按钮处展开的暗色浮层菜单，[sections] 之间以粗分隔线分组
Future<void> showPlayerPopoverMenu(
  BuildContext anchorContext,
  List<List<PlayerMenuItem>> sections,
) async {
  final navigator = Navigator.of(anchorContext, rootNavigator: true);
  final overlay = navigator.overlay!.context.findRenderObject()! as RenderBox;
  final box = anchorContext.findRenderObject()! as RenderBox;
  final anchor = MatrixUtils.transformRect(
    box.getTransformTo(overlay),
    Offset.zero & box.size,
  );
  final action = await navigator.push(
    _PlayerPopoverRoute(
      anchor: anchor,
      sections: sections.where((s) => s.isNotEmpty).toList(),
    ),
  );
  await action?.call();
}

class _PlayerPopoverRoute extends PopupRoute<FutureOr<void> Function()> {
  _PlayerPopoverRoute({required this.anchor, required this.sections});

  final Rect anchor;
  final List<List<PlayerMenuItem>> sections;

  static const _margin = 8.0;
  static const _gap = 6.0;
  static const _maxWidth = 280.0;
  static const _maxHeight = 480.0;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => 'Dismiss';

  @override
  Duration get transitionDuration => const Duration(milliseconds: 240);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 160);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final size = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);
    final bounds = Rect.fromLTRB(
      padding.left + _margin,
      padding.top + _margin,
      size.width - padding.right - _margin,
      size.height - padding.bottom - _margin,
    );
    final spaceAbove = anchor.top - _gap - bounds.top;
    final spaceBelow = bounds.bottom - anchor.bottom - _gap;
    final above = spaceAbove >= spaceBelow;
    final alignLeft = anchor.center.dx < size.width / 2;
    final left = math.max(anchor.left, bounds.left);
    final right = math.min(anchor.right, bounds.right);
    final maxWidth = math.min(
      _maxWidth,
      alignLeft ? bounds.right - left : right - bounds.left,
    );
    final maxHeight = math.min(_maxHeight, above ? spaceAbove : spaceBelow);

    final scale = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeInCubic,
    );
    final fade = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
    );

    return Stack(
      children: [
        Positioned(
          left: alignLeft ? left : null,
          right: alignLeft ? null : size.width - right,
          top: above ? null : anchor.bottom + _gap,
          bottom: above ? size.height - anchor.top + _gap : null,
          child: FadeTransition(
            opacity: fade,
            child: ScaleTransition(
              scale: Tween(begin: 0.8, end: 1.0).animate(scale),
              alignment:
                  above
                      ? (alignLeft
                          ? Alignment.bottomLeft
                          : Alignment.bottomRight)
                      : (alignLeft ? Alignment.topLeft : Alignment.topRight),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: math.min(168, maxWidth),
                  maxWidth: maxWidth,
                  maxHeight: math.max(0, maxHeight),
                ),
                child: _PlayerPopoverMenu(sections: sections),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PlayerPopoverMenu extends StatefulWidget {
  final List<List<PlayerMenuItem>> sections;

  const _PlayerPopoverMenu({required this.sections});

  @override
  State<_PlayerPopoverMenu> createState() => _PlayerPopoverMenuState();
}

class _PlayerPopoverMenuState extends State<_PlayerPopoverMenu> {
  static const _radius = BorderRadius.all(Radius.circular(14));
  static const _hairline = Color(0x1AFFFFFF);
  static const _divider = ColoredBox(
    color: _hairline,
    child: SizedBox(height: 0.5),
  );
  static const _sectionGap = ColoredBox(
    color: Color(0x40000000),
    child: SizedBox(height: 6),
  );

  final _selectedKey = GlobalKey();
  PlayerMenuItem? _picked;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _selectedKey.currentContext;
      if (ctx != null) Scrollable.ensureVisible(ctx, alignment: 0.5);
    });
  }

  void _onTap(PlayerMenuItem item) {
    if (_closing) return;
    _closing = true;
    final navigator = Navigator.of(context);
    if (item.onAction != null) {
      navigator.pop(item.onAction);
      return;
    }
    item.onSelected!();
    setState(() => _picked = item);
    final route = ModalRoute.of(context);
    Future.delayed(const Duration(milliseconds: 140), () {
      if (route?.isCurrent ?? false) navigator.pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    final initial =
        widget.sections
            .expand((s) => s)
            .where((item) => item.selected == true)
            .firstOrNull;
    for (var i = 0; i < widget.sections.length; i++) {
      if (i > 0) rows.add(_sectionGap);
      final section = widget.sections[i];
      for (var j = 0; j < section.length; j++) {
        if (j > 0) rows.add(_divider);
        final item = section[j];
        final selected =
            item.selected != null &&
            (_picked != null ? identical(item, _picked) : item.selected!);
        rows.add(
          _PlayerPopoverRow(
            key: identical(item, initial) ? _selectedKey : null,
            item: item,
            selected: selected,
            onTap: item.enabled ? () => _onTap(item) : null,
          ),
        );
      }
    }

    return Focus(
      autofocus: true,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          borderRadius: _radius,
          boxShadow: [
            BoxShadow(
              color: Color(0x59000000),
              blurRadius: 24,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: _radius,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xF2232325),
              borderRadius: _radius,
              border: Border.all(color: _hairline, width: 0.5),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: IntrinsicWidth(
                child: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(
                    context,
                  ).copyWith(scrollbars: false),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: rows,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlayerPopoverRow extends StatefulWidget {
  final PlayerMenuItem item;
  final bool selected;
  final VoidCallback? onTap;

  const _PlayerPopoverRow({
    super.key,
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_PlayerPopoverRow> createState() => _PlayerPopoverRowState();
}

class _PlayerPopoverRowState extends State<_PlayerPopoverRow> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final isDesktop = WindowControls.isDesktop;
    final enabled = widget.onTap != null;
    final item = widget.item;
    final foreground = enabled ? Colors.white : Colors.white38;

    final Widget? leading;
    if (item.icon != null) {
      leading = Icon(item.icon, size: 16, color: Colors.white70);
    } else if (item.selected != null) {
      leading = AnimatedScale(
        scale: widget.selected ? 1 : 0,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutBack,
        child: const Icon(LucideIcons.check, size: 16, color: Colors.white),
      );
    } else {
      leading = null;
    }

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          height: isDesktop ? 36 : 44,
          padding: const EdgeInsets.only(left: 12, right: 16),
          color:
              !enabled
                  ? Colors.transparent
                  : _pressed
                  ? const Color(0x24FFFFFF)
                  : _hovered
                  ? const Color(0x14FFFFFF)
                  : Colors.transparent,
          child: Row(
            children: [
              SizedBox(width: 26, child: leading),
              Expanded(
                child: Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foreground,
                    fontSize: isDesktop ? 14 : 15,
                    fontWeight:
                        widget.selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
