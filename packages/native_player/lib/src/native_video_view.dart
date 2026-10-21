import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'generated/native_player_api.g.dart';

/// 承载原生播放画面的 PlatformView；原生侧按 playerId 找到播放器实例
class NativeVideoView extends StatefulWidget {
  const NativeVideoView({
    super.key,
    required this.playerId,
    required this.fit,
    required this.onFitChanged,
  });

  static const viewType = 'native_player/video';

  final int playerId;
  final NativeVideoFit fit;
  final ValueChanged<NativeVideoFit> onFitChanged;

  @override
  State<NativeVideoView> createState() => _NativeVideoViewState();
}

class _NativeVideoViewState extends State<NativeVideoView> {
  @override
  void didUpdateWidget(covariant NativeVideoView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.fit != oldWidget.fit) widget.onFitChanged(widget.fit);
  }

  @override
  Widget build(BuildContext context) {
    final params = {'playerId': widget.playerId, 'fit': widget.fit.index};
    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS => UiKitView(
        viewType: NativeVideoView.viewType,
        creationParams: params,
        creationParamsCodec: const StandardMessageCodec(),
      ),
      TargetPlatform.macOS => AppKitView(
        viewType: NativeVideoView.viewType,
        creationParams: params,
        creationParamsCodec: const StandardMessageCodec(),
      ),
      _ => const SizedBox.expand(),
    };
  }
}
