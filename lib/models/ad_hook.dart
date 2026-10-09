/// One of the 5 opening-hook candidates the Hook-First Engine generates
/// for a campaign — mirrors backend ads_studio.py's HookOut. [scoreTotal]
/// is a server-computed weighted sum of the five dimension scores, never
/// trusted straight from the model — see ads_studio.py's
/// HOOK_SCORE_WEIGHTS for the (editable) weighting. A high score is a
/// relative ranking signal, not a guarantee of real performance.
class AdHook {
  final String id;
  final String hookText;
  final String angle;
  final String rationale;
  final int scoreAttention;
  final int scoreCuriosity;
  final int scoreEmotional;
  final int scoreRelevance;
  final int scoreTransition;
  final double scoreTotal;
  final int rank;
  final bool selected;

  const AdHook({
    required this.id,
    required this.hookText,
    required this.angle,
    required this.rationale,
    required this.scoreAttention,
    required this.scoreCuriosity,
    required this.scoreEmotional,
    required this.scoreRelevance,
    required this.scoreTransition,
    required this.scoreTotal,
    required this.rank,
    required this.selected,
  });

  factory AdHook.fromJson(Map<String, dynamic> json) => AdHook(
        id: json['id'] as String,
        hookText: json['hook_text'] ?? '',
        angle: json['angle'] ?? '',
        rationale: json['rationale'] ?? '',
        scoreAttention: (json['score_attention'] as num?)?.toInt() ?? 0,
        scoreCuriosity: (json['score_curiosity'] as num?)?.toInt() ?? 0,
        scoreEmotional: (json['score_emotional'] as num?)?.toInt() ?? 0,
        scoreRelevance: (json['score_relevance'] as num?)?.toInt() ?? 0,
        scoreTransition: (json['score_transition'] as num?)?.toInt() ?? 0,
        scoreTotal: (json['score_total'] as num?)?.toDouble() ?? 0,
        rank: (json['rank'] as num?)?.toInt() ?? 0,
        selected: json['selected'] == true,
      );
}
