/// "Why This Worked" — a plain-language explanation of how one specific
/// post performed, grounded in this creator's own real numbers (never
/// reach/algorithm claims Viyo has no data to back up).
class PostInsight {
  final int engagement;
  final double? baselineAvgEngagement;
  final String? performance; // 'above' | 'about' | 'below' | null
  final String explanation;

  PostInsight({
    required this.engagement,
    this.baselineAvgEngagement,
    this.performance,
    required this.explanation,
  });

  factory PostInsight.fromJson(Map<String, dynamic> json) => PostInsight(
        engagement: (json['engagement'] as num?)?.toInt() ?? 0,
        baselineAvgEngagement: (json['baseline_avg_engagement'] as num?)?.toDouble(),
        performance: json['performance'] as String?,
        explanation: json['explanation'] as String? ?? '',
      );
}
