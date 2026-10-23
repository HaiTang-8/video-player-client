import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../../domain/subtitle_style.dart';

/// mpv 的文本字幕叠加层：按视频实际显示区域排版，样式来自 [style]
class MpvSubtitleOverlay extends StatefulWidget {
  const MpvSubtitleOverlay({
    super.key,
    required this.player,
    required this.style,
    required this.fit,
  });

  final Player player;
  final ValueListenable<SubtitleStyle> style;
  final BoxFit fit;

  /// 标准字号占视频高度的比例
  static const baseSizeFraction = 0.055;

  @override
  State<MpvSubtitleOverlay> createState() => _MpvSubtitleOverlayState();
}

class _MpvSubtitleOverlayState extends State<MpvSubtitleOverlay> {
  late String _text = _join(widget.player.state.subtitle);
  late Size _videoSize = _size(
    widget.player.state.width,
    widget.player.state.height,
  );
  final List<StreamSubscription> _subscriptions = [];

  @override
  void initState() {
    super.initState();
    final stream = widget.player.stream;
    _subscriptions
      ..add(stream.subtitle.listen((v) => setState(() => _text = _join(v))))
      ..add(stream.width.listen((_) => _updateSize()))
      ..add(stream.height.listen((_) => _updateSize()));
  }

  @override
  void dispose() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    super.dispose();
  }

  void _updateSize() {
    final state = widget.player.state;
    setState(() => _videoSize = _size(state.width, state.height));
  }

  static Size _size(int? width, int? height) =>
      width != null && height != null && width > 0 && height > 0
          ? Size(width.toDouble(), height.toDouble())
          : Size.zero;

  static String _join(List<String> lines) => [
    for (final line in lines)
      if (line.trim().isNotEmpty) line.trim(),
  ].join('\n');

  @override
  Widget build(BuildContext context) {
    if (_text.isEmpty) return const SizedBox.shrink();
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final box = constraints.biggest;
          final video = _videoRect(box);
          return ValueListenableBuilder<SubtitleStyle>(
            valueListenable: widget.style,
            builder: (context, style, _) {
              final fontSize =
                  video.height *
                  MpvSubtitleOverlay.baseSizeFraction *
                  style.scale;
              final bottom =
                  box.height - video.bottom + video.height * style.bottomMargin;
              final text = Text(
                _text,
                textAlign: TextAlign.center,
                textScaler: TextScaler.noScaling,
                style: TextStyle(
                  fontFamily: 'HarmonyOS_Sans',
                  fontWeight: FontWeight.w500,
                  fontSize: fontSize,
                  height: 1.3,
                  color: Color(style.color),
                  decoration: TextDecoration.none,
                ),
              );
              return Stack(
                children: [
                  Positioned(
                    left: video.left + fontSize,
                    right: box.width - video.right + fontSize,
                    bottom: bottom,
                    child: Center(
                      child:
                          style.backgroundOpacity > 0
                              ? DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(
                                    alpha: style.backgroundOpacity,
                                  ),
                                  borderRadius: BorderRadius.circular(
                                    fontSize * 0.25,
                                  ),
                                ),
                                child: Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: fontSize * 0.4,
                                    vertical: fontSize * 0.18,
                                  ),
                                  child: text,
                                ),
                              )
                              : text,
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  /// 视频画面在布局区域中的可见部分；尺寸未知时按整个区域
  Rect _videoRect(Size box) {
    final rect = Offset.zero & box;
    if (_videoSize.isEmpty || box.isEmpty) return rect;
    final fitted = applyBoxFit(widget.fit, _videoSize, box).destination;
    return Alignment.center.inscribe(fitted, rect).intersect(rect);
  }
}
