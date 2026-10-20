import 'engine_selection_rule.dart';

/// 按顺序评估规则，返回第一条给出可用候选的决策
class EngineSelector {
  const EngineSelector(this.rules);

  final List<EngineSelectionRule> rules;

  EngineDecision select(EngineSelectionContext context) {
    for (final rule in rules) {
      final decision = rule.evaluate(context);
      if (decision == null) continue;
      final candidates =
          decision.candidates
              .where((kind) => !context.failedKinds.contains(kind))
              .toList();
      if (candidates.isNotEmpty) {
        return EngineDecision(candidates, decision.reason);
      }
    }
    return const EngineDecision([], '没有可用的播放内核');
  }
}
