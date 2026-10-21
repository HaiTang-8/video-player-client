import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'domain/playback_domain.dart';
import 'engines/mpv/mpv_texture_engine.dart';
import 'engines/native/native_playback_engine.dart';
import 'engines/playback_engine_factory.dart';
import 'selection/engine_selection_rule.dart';
import 'selection/engine_selector.dart';
import 'selection/platform_environment.dart';

/// 原生引擎渲染字幕用的字体，与全局界面字体保持一致
const subtitleFontAssets = [
  'assets/fonts/HarmonyOS_Sans_SC_Regular.ttf',
  'assets/fonts/HarmonyOS_Sans_SC_Bold.ttf',
];

final platformEnvironmentProvider = Provider<PlatformEnvironment>(
  (ref) => PlatformEnvironment.current(),
);

final engineSelectorProvider = Provider<EngineSelector>(
  (ref) => const EngineSelector([
    AppleAetherRule(),
    AndroidMedia3Rule(),
    DefaultMpvTextureRule(),
  ]),
);

final playbackEngineFactoryProvider = Provider<PlaybackEngineFactory>(
  (ref) => PlaybackEngineFactory({
    PlaybackEngineKind.mpvTexture: MpvTextureEngine.new,
    PlaybackEngineKind.aether:
        () => NativePlaybackEngine(
          kind: PlaybackEngineKind.aether,
          initialCapabilities: const EngineCapabilities(
            dolbyVisionColor: true,
            maxVolume: 1.0,
            maxRate: 2.0,
          ),
          subtitleFontAssets: subtitleFontAssets,
        ),
    // 真实能力在 initialize 时由原生返回（是否有杜比视界解码器）
    PlaybackEngineKind.media3:
        () => NativePlaybackEngine(
          kind: PlaybackEngineKind.media3,
          initialCapabilities: const EngineCapabilities(
            dolbyVisionColor: false,
            maxVolume: 1.0,
            maxRate: 3.0,
          ),
        ),
  }),
);
