import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/playback/domain/playback_domain.dart';
import 'package:media_player/playback/selection/engine_selection_rule.dart';
import 'package:media_player/playback/selection/engine_selector.dart';
import 'package:media_player/playback/selection/platform_environment.dart';

class _IosOnlyRule implements EngineSelectionRule {
  const _IosOnlyRule();

  @override
  EngineDecision? evaluate(EngineSelectionContext context) =>
      context.environment.platform == TargetPlatform.iOS
          ? const EngineDecision([
            PlaybackEngineKind.aether,
            PlaybackEngineKind.mpvTexture,
          ], 'ios')
          : null;
}

void main() {
  const selector = EngineSelector([_IosOnlyRule(), DefaultMpvTextureRule()]);

  EngineSelectionContext context(
    TargetPlatform platform, {
    Set<PlaybackEngineKind> failed = const {},
  }) => EngineSelectionContext(
    environment: PlatformEnvironment(platform: platform),
    failedKinds: failed,
  );

  test('first matching rule wins', () {
    final decision = selector.select(context(TargetPlatform.iOS));
    expect(decision.candidates, [
      PlaybackEngineKind.aether,
      PlaybackEngineKind.mpvTexture,
    ]);
    expect(decision.reason, 'ios');
  });

  test('skipped rule falls through to the next one', () {
    final decision = selector.select(context(TargetPlatform.windows));
    expect(decision.candidates, [PlaybackEngineKind.mpvTexture]);
  });

  test('failed kinds are removed from candidates', () {
    final decision = selector.select(
      context(TargetPlatform.iOS, failed: {PlaybackEngineKind.aether}),
    );
    expect(decision.candidates, [PlaybackEngineKind.mpvTexture]);
  });

  test('returns empty decision when every candidate failed', () {
    final decision = selector.select(
      context(TargetPlatform.windows, failed: {PlaybackEngineKind.mpvTexture}),
    );
    expect(decision.candidates, isEmpty);
  });
}
