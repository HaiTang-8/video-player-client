import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'cache/playback_cache_catalog.dart';
import 'cache/playback_proxy.dart';
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

/// 当前平台是否启用播放缓存（见 [PlaybackCacheConfig.supported]）
final playbackCacheSupportedProvider = Provider<bool>(
  (ref) => PlaybackCacheConfig.supported,
);

final playbackCacheCatalogProvider = Provider<PlaybackCacheCatalog>(
  (ref) => PlaybackProxy.instance,
);

final platformEnvironmentProvider = Provider<PlatformEnvironment>(
  (ref) => PlatformEnvironment.current(),
);

final engineSelectorProvider = Provider<EngineSelector>(
  (ref) => const EngineSelector([
    AppleAetherRule(),
    CompatibilityModeRule(),
    AndroidMedia3Rule(),
    DefaultMpvTextureRule(),
  ]),
);

/// 两种偏好选出的内核不同时才提供“播放内核”设置
final enginePreferenceAvailableProvider = Provider<bool>((ref) {
  final selector = ref.watch(engineSelectorProvider);
  final environment = ref.watch(platformEnvironmentProvider);
  List<PlaybackEngineKind> candidates(EnginePreference preference) =>
      selector
          .select(
            EngineSelectionContext(
              environment: environment,
              preference: preference,
            ),
          )
          .candidates;
  return !listEquals(
    candidates(EnginePreference.auto),
    candidates(EnginePreference.compatibility),
  );
});

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
            reportsVideoView: true,
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
            reportsVideoView: true,
          ),
        ),
  }),
);
