import 'package:flutter/widgets.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../domain/playback_domain.dart';
import 'mpv_engine_base.dart';
import 'mpv_subtitle_overlay.dart';

/// 现有的 media_kit 纹理渲染路径
class MpvTextureEngine extends MpvEngineBase {
  MpvTextureEngine() {
    _controller = VideoController(player);
  }

  late final VideoController _controller;

  @override
  PlaybackEngineKind get kind => PlaybackEngineKind.mpvTexture;

  @override
  Widget buildVideoView(BuildContext context, {required BoxFit fit}) => Stack(
    fit: StackFit.expand,
    children: [
      Video(
        controller: _controller,
        controls: NoVideoControls,
        fit: fit,
        subtitleViewConfiguration: const SubtitleViewConfiguration(
          visible: false,
        ),
      ),
      MpvSubtitleOverlay(player: player, style: subtitleStyle, fit: fit),
    ],
  );
}
