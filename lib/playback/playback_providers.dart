import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'domain/playback_domain.dart';
import 'engines/mpv/mpv_texture_engine.dart';
import 'engines/playback_engine_factory.dart';
import 'selection/engine_selection_rule.dart';
import 'selection/engine_selector.dart';
import 'selection/platform_environment.dart';

final platformEnvironmentProvider = Provider<PlatformEnvironment>(
  (ref) => PlatformEnvironment.current(),
);

final engineSelectorProvider = Provider<EngineSelector>(
  (ref) => const EngineSelector([DefaultMpvTextureRule()]),
);

final playbackEngineFactoryProvider = Provider<PlaybackEngineFactory>(
  (ref) => const PlaybackEngineFactory({
    PlaybackEngineKind.mpvTexture: MpvTextureEngine.new,
  }),
);
