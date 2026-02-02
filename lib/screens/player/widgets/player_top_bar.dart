import 'package:flutter/material.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' show LucideIcons;

import '../../../core/widgets/app_back_button.dart';
import '../../../core/window/window_controls.dart';

class PlayerTopBar extends StatelessWidget {
  final String title;
  final VoidCallback? onBack;
  final bool isLocked;
  final bool useGradient;
  final bool useSafeArea;

  const PlayerTopBar({
    super.key,
    required this.title,
    this.onBack,
    this.isLocked = false,
    this.useGradient = true,
    this.useSafeArea = true,
  });

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.of(context).padding;
    const horizontalPadding = 12.0;
    final leftPadding = WindowControls.isMacOS ? 68.0 : horizontalPadding;
    const barHeight = 44.0;

    final barContent = SizedBox(
      height: barHeight,
      child: Stack(
        children: [
          if (WindowControls.isDesktop)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onPanStart: (_) => WindowControls.startDrag(),
                onDoubleTap: () => WindowControls.toggleMaximize(),
              ),
            ),
          Positioned.fill(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (!isLocked) ...[
                  AppBackButton(
                    onPressed: onBack ?? () => Navigator.of(context).pop(),
                    color: Colors.white,
                    leftPadding: 0,
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (WindowControls.isWindows) ...[
                  const SizedBox(width: 16),
                  _WindowCaptionButton(
                    icon: LucideIcons.minus,
                    onPressed: () => WindowControls.minimize(),
                  ),
                  _WindowCaptionButton(
                    icon: LucideIcons.square,
                    onPressed: () => WindowControls.toggleMaximize(),
                  ),
                  _WindowCaptionButton(
                    icon: LucideIcons.x,
                    hoverColor: const Color(0xFFE81123),
                    onPressed: () => WindowControls.close(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );

    final edgeInsets = EdgeInsets.only(
      top: useSafeArea && !WindowControls.isDesktop ? (padding.top + 10) : 0,
      left: (useSafeArea ? padding.left : 0) + leftPadding,
      right: (useSafeArea ? padding.right : 0) + (WindowControls.isWindows ? 0 : horizontalPadding),
      bottom: useSafeArea && !WindowControls.isDesktop ? 10 : 0,
    );

    final Widget decorated;
    if (useGradient) {
      decorated = DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black54, Colors.transparent],
          ),
        ),
        child: Padding(
          padding: edgeInsets,
          child: Material(
            color: Colors.transparent,
            child: barContent,
          ),
        ),
      );
    } else {
      decorated = Container(
        color: Colors.black,
        padding: edgeInsets,
        child: barContent,
      );
    }

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: decorated,
    );
  }
}

class _WindowCaptionButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final Color? hoverColor;

  const _WindowCaptionButton({
    required this.icon,
    required this.onPressed,
    this.hoverColor,
  });

  @override
  State<_WindowCaptionButton> createState() => _WindowCaptionButtonState();
}

class _WindowCaptionButtonState extends State<_WindowCaptionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final bg = _hovered ? (widget.hoverColor ?? Colors.white24) : Colors.transparent;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: Container(
          width: 46,
          height: 44,
          color: bg,
          child: Center(child: Icon(widget.icon, color: Colors.white)),
        ),
      ),
    );
  }
}
