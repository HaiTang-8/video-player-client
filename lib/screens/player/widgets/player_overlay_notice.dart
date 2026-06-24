import 'package:flutter/material.dart';

enum PlayerOverlayNoticePosition { center, top }

class PlayerOverlayNotice extends StatelessWidget {
  final IconData? icon;
  final String? text;
  final String? secondaryText;
  final double? progress;
  final Color color;
  final PlayerOverlayNoticePosition position;
  final EdgeInsets safePadding;

  const PlayerOverlayNotice({
    super.key,
    this.icon,
    this.text,
    this.secondaryText,
    this.progress,
    this.color = Colors.white,
    this.position = PlayerOverlayNoticePosition.center,
    this.safePadding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(8),
      ),
      child: _buildContent(),
    );

    if (position == PlayerOverlayNoticePosition.top) {
      return Positioned(
        top: safePadding.top + 20,
        left: 0,
        right: 0,
        child: Center(child: content),
      );
    }

    return Center(child: content);
  }

  Widget _buildContent() {
    final progressValue = progress?.clamp(0.0, 1.0);
    final hasProgress = progressValue != null;
    final hasIcon = icon != null;
    final hasMainText = text != null && text!.isNotEmpty;
    final hasSecondaryText = secondaryText != null && secondaryText!.isNotEmpty;

    if (hasProgress) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasIcon) Icon(icon, color: color),
          if (hasIcon) const SizedBox(width: 12),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (hasMainText)
                Text(
                  text!,
                  style: TextStyle(
                    color: color,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              if (hasMainText) const SizedBox(height: 6),
              SizedBox(
                width: 100,
                child: LinearProgressIndicator(
                  value: progressValue,
                  backgroundColor: Colors.white24,
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
            ],
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hasIcon) Icon(icon, color: color),
        if (hasIcon && hasMainText) const SizedBox(height: 8),
        if (hasMainText)
          Text(
            text!,
            style: TextStyle(
              color: color,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        if (hasSecondaryText) const SizedBox(height: 4),
        if (hasSecondaryText)
          Text(
            secondaryText!,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
      ],
    );
  }
}
