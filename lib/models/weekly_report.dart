class WeeklyReport {
  final int postsThisWeek;
  final double? avgScoreThisWeek;
  final double? avgScoreLastWeek;
  final String? scoreTrend; // 'up' | 'down' | 'flat' | null
  final int totalLikes;
  final int totalComments;
  final String? bestPostCaption;
  final String summary;

  WeeklyReport({
    required this.postsThisWeek,
    this.avgScoreThisWeek,
    this.avgScoreLastWeek,
    this.scoreTrend,
    required this.totalLikes,
    required this.totalComments,
    this.bestPostCaption,
    required this.summary,
  });

  factory WeeklyReport.fromJson(Map<String, dynamic> json) => WeeklyReport(
        postsThisWeek: (json['posts_this_week'] as num?)?.toInt() ?? 0,
        avgScoreThisWeek: (json['avg_score_this_week'] as num?)?.toDouble(),
        avgScoreLastWeek: (json['avg_score_last_week'] as num?)?.toDouble(),
        scoreTrend: json['score_trend'] as String?,
        totalLikes: (json['total_likes'] as num?)?.toInt() ?? 0,
        totalComments: (json['total_comments'] as num?)?.toInt() ?? 0,
        bestPostCaption: json['best_post_caption'] as String?,
        summary: json['summary'] as String? ?? '',
      );
}
