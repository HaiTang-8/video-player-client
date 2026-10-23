import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
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
    this.onCreated,
    this.onDisposed,
  });

  static const viewType = 'native_player/video';

  final int playerId;
  final NativeVideoFit fit;
  final ValueChanged<NativeVideoFit> onFitChanged;

  /// 原生视图已创建（下一帧即参与合成）
  final VoidCallback? onCreated;
  final VoidCallback? onDisposed;

  @override
  State<NativeVideoView> createState() => _NativeVideoViewState();
}

class _NativeVideoViewState extends State<NativeVideoView> {
  @override
  void dispose() {
    widget.onDisposed?.call();
    super.dispose();
  }

  void _created(int _) => widget.onCreated?.call();

  @override
  void didUpdateWidget(covariant NativeVideoView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.fit != oldWidget.fit) widget.onFitChanged(widget.fit);
  }

  @override
  Widget build(BuildContext context) {
    final params = {'playerId': widget.playerId, 'fit': widget.fit.index};
    // 画面不接收触摸，手势全部交给上层的 Flutter 控制层
    return IgnorePointer(child: _platformView(params));
  }

  Widget _platformView(Map<String, Object> params) {
    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS => UiKitView(
        viewType: NativeVideoView.viewType,
        creationParams: params,
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: _created,
      ),
      TargetPlatform.macOS => AppKitView(
        viewType: NativeVideoView.viewType,
        creationParams: params,
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: _created,
      ),
      // Hybrid Composition：SurfaceView 直接送显，HDR 输出需要这种方式
      TargetPlatform.android => PlatformViewLink(
        viewType: NativeVideoView.viewType,
        surfaceFactory: (context, controller) => AndroidViewSurface(
          controller: controller as AndroidViewController,
          gestureRecognizers: const {},
          hitTestBehavior: PlatformViewHitTestBehavior.transparent,
        ),
        onCreatePlatformView: (creation) =>
            PlatformViewsService.initExpensiveAndroidView(
                id: creation.id,
                viewType: NativeVideoView.viewType,
                layoutDirection: TextDirection.ltr,
                creationParams: params,
                creationParamsCodec: const StandardMessageCodec(),
              )
              ..addOnPlatformViewCreatedListener(creation.onPlatformViewCreated)
              ..addOnPlatformViewCreatedListener(_created)
              ..create(),
      ),
      _ => const SizedBox.expand(),
    };
  }
}
