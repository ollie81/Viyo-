class CreatorStats {
  final int totalPosts;
  final int postsLast30Days;
  final int totalLikesReceived;
  final int totalCommentsReceived;
  final int followers;
  final int following;
  final int missionsCompleted30Days;
  final int aiFeedbackCount;

  CreatorStats({
    required this.totalPosts,
    required this.postsLast30Days,
    required this.totalLikesReceived,
    required this.totalCommentsReceived,
    required this.followers,
    required this.following,
    required this.missionsCompleted30Days,
    required this.aiFeedbackCount,
  });

  factory CreatorStats.fromJson(Map<String, dynamic> json) => CreatorStats(
        totalPosts: json['total_posts'] ?? 0,
        postsLast30Days: json['posts_last_30_days'] ?? 0,
        totalLikesReceived: json['total_likes_received'] ?? 0,
        totalCommentsReceived: json['total_comments_received'] ?? 0,
        followers: json['followers'] ?? 0,
        following: json['following'] ?? 0,
        missionsCompleted30Days: json['missions_completed_30_days'] ?? 0,
        aiFeedbackCount: json['ai_feedback_count'] ?? 0,
      );
}

