import 'package:flutter/foundation.dart';

import '../domain/playback_domain.dart';
import 'platform_environment.dart';

class EngineSelectionContext {
  final PlatformEnvironment environment;

  /// 本次会话中已经失败的内核，选择时会被剔除
  final Set<PlaybackEngineKind> failedKinds;

  const EngineSelectionContext({
    required this.environment,
    this.failedKinds = const {},
  });
}

class EngineDecision {
  /// 按优先级排序，会话按顺序回退
  final List<PlaybackEngineKind> candidates;
  final String reason;

  const EngineDecision(this.candidates, this.reason);
}

abstract interface class EngineSelectionRule {
  /// 返回 null 表示交给下一条规则
  EngineDecision? evaluate(EngineSelectionContext context);
}

/// iOS / macOS 只打包 AetherEngine（两套 FFmpeg 不能共存），没有 mpv 兜底
class AppleAetherRule implements EngineSelectionRule {
  const AppleAetherRule();

  @override
  EngineDecision? evaluate(EngineSelectionContext context) {
    final platform = context.environment.platform;
    if (platform != TargetPlatform.iOS && platform != TargetPlatform.macOS) {
      return null;
    }
    return const EngineDecision([
      PlaybackEngineKind.aether,
    ], 'Apple 平台使用 AetherEngine');
  }
}

class DefaultMpvTextureRule implements EngineSelectionRule {
  const DefaultMpvTextureRule();

  @override
  EngineDecision evaluate(EngineSelectionContext context) =>
      const EngineDecision([PlaybackEngineKind.mpvTexture], '默认内核');
}
