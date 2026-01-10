import 'package:flutter/material.dart';

import '../window/window_controls.dart';

class DesktopTitleBar extends StatelessWidget implements PreferredSizeWidget {
  final Widget? leading;
  final Widget? title;
  final List<Widget> actions;
  final double height;
  final bool centerTitle;
  final bool enableDrag;
  final bool titleInteractive;
  final Color? backgroundColor;
  final Color? foregroundColor;

  const DesktopTitleBar({
    super.key,
    this.leading,
    this.title,
    this.actions = const [],
    this.height = 40,
    this.centerTitle = true,
    this.enableDrag = true,
    this.titleInteractive = false,
    this.backgroundColor,
    this.foregroundColor,
  });

  @override
  Size get preferredSize => Size.fromHeight(height);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg =
        backgroundColor ??
        theme.appBarTheme.backgroundColor ??
        theme.colorScheme.surface;
    final fg =
        foregroundColor ??
        theme.appBarTheme.foregroundColor ??
        theme.colorScheme.onSurface;
    final dividerColor = theme.dividerColor.withValues(alpha: 0.2);

    final leftInset = WindowControls.isMacOS ? 72.0 : 0.0;

    return Material(
      color: bg,
      child: IconTheme(
        data: IconThemeData(color: fg),
        child: DefaultTextStyle(
          style: (theme.textTheme.titleMedium ?? const TextStyle()).copyWith(
            color: fg,
          ),
          child: Container(
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: dividerColor)),
            ),
            child: SizedBox(
              height: height,
              child: Stack(
                children: [
                  if (enableDrag && WindowControls.isDesktop)
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onPanStart: (_) => WindowControls.startDrag(),
                        onDoubleTap: () => WindowControls.toggleMaximize(),
                      ),
                    ),
                  if (centerTitle && title != null)
                    Positioned.fill(
                      child: Center(
                        child: titleInteractive ? title! : IgnorePointer(child: title!),
                      ),
                    ),
                  Row(
                    children: [
                      SizedBox(width: leftInset),
                      if (leading != null) leading!,
                      if (!centerTitle && title != null) ...[
                        const SizedBox(width: 4),
                        titleInteractive ? title! : IgnorePointer(child: title!),
                      ],
                      const Spacer(),
                      ...actions,
                      if (WindowControls.isWindows && actions.isNotEmpty)
                        const SizedBox(width: 16),
                      if (WindowControls.isWindows)
                        _WindowCaptionButtons(height: height, foregroundColor: fg)
                      else
                        const SizedBox(width: 12),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WindowCaptionButtons extends StatefulWidget {
  final double height;
  final Color foregroundColor;

  const _WindowCaptionButtons({
    required this.height,
    required this.foregroundColor,
  });

  @override
  State<_WindowCaptionButtons> createState() => _WindowCaptionButtonsState();
}

class _WindowCaptionButtonsState extends State<_WindowCaptionButtons>
    with WidgetsBindingObserver {
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkMaximized();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    _checkMaximized();
  }

  Future<void> _checkMaximized() async {
    final maximized = await WindowControls.isMaximized();
    if (mounted && maximized != _isMaximized) {
      setState(() => _isMaximized = maximized);
    }
  }

  Future<void> _toggleMaximize() async {
    await WindowControls.toggleMaximize();
    _checkMaximized();
  }

  @override
  Widget build(BuildContext context) {
    final hoverBg = widget.foregroundColor.withValues(alpha: 0.08);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _WindowCaptionButton(
          height: widget.height,
          icon: Icons.remove,
          foregroundColor: widget.foregroundColor,
          hoverBackgroundColor: hoverBg,
          onPressed: () => WindowControls.minimize(),
        ),
        _WindowCaptionButton(
          height: widget.height,
          icon: _isMaximized ? Icons.filter_none : Icons.crop_square,
          foregroundColor: widget.foregroundColor,
          hoverBackgroundColor: hoverBg,
          onPressed: _toggleMaximize,
        ),
        _WindowCaptionButton(
          height: widget.height,
          icon: Icons.close,
          foregroundColor: widget.foregroundColor,
          hoverBackgroundColor: const Color(0xFFE81123),
          hoverForegroundColor: Colors.white,
          onPressed: () => WindowControls.close(),
        ),
      ],
    );
  }
}

class _WindowCaptionButton extends StatefulWidget {
  final double height;
  final IconData icon;
  final Color foregroundColor;
  final Color hoverBackgroundColor;
  final Color? hoverForegroundColor;
  final VoidCallback onPressed;

  const _WindowCaptionButton({
    required this.height,
    required this.icon,
    required this.foregroundColor,
    required this.hoverBackgroundColor,
    required this.onPressed,
    this.hoverForegroundColor,
  });

  @override
  State<_WindowCaptionButton> createState() => _WindowCaptionButtonState();
}

class _WindowCaptionButtonState extends State<_WindowCaptionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final bg = _hovered ? widget.hoverBackgroundColor : Colors.transparent;
    final fg =
        _hovered
            ? (widget.hoverForegroundColor ?? widget.foregroundColor)
            : widget.foregroundColor;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: bg,
        child: InkWell(
          onTap: widget.onPressed,
          child: SizedBox(
            width: 46,
            height: widget.height,
            child: Center(child: Icon(widget.icon, size: 16, color: fg)),
          ),
        ),
      ),
    );
  }
}
