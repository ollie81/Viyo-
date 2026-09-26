/// Creator-facing analytics for one series — mirrors series_analytics.py's
/// SeriesAnalyticsResponse/EpisodeAnalytics exactly.
class EpisodeAnalytics {
  final String postId;
  final int episodeNumber;
  final int viewCount;
  final int likeCount;
  final int commentCount;
  final int uniqueViewers;
  // Null (not 0) means "not enough watch data yet" — see the backend's
  // own doc comment on why that's a real distinction, not a display nit.
  final double? completionRate;
  final double? averageWatchedFraction;

  const EpisodeAnalytics({
    required this.postId,
    required this.episodeNumber,
    required this.viewCount,
    required this.likeCount,
    required this.commentCount,
    required this.uniqueViewers,
    this.completionRate,
    this.averageWatchedFraction,
  });

  factory EpisodeAnalytics.fromJson(Map<String, dynamic> json) => EpisodeAnalytics(
        postId: json['post_id'] as String,
        episodeNumber: (json['episode_number'] as num?)?.toInt() ?? 0,
        viewCount: (json['view_count'] as num?)?.toInt() ?? 0,
        likeCount: (json['like_count'] as num?)?.toInt() ?? 0,
        commentCount: (json['comment_count'] as num?)?.toInt() ?? 0,
        uniqueViewers: (json['unique_viewers'] as num?)?.toInt() ?? 0,
        completionRate: (json['completion_rate'] as num?)?.toDouble(),
        averageWatchedFraction: (json['average_watched_fraction'] as num?)?.toDouble(),
      );
}

class SeriesAnalytics {
  final String seriesId;
  final int totalViews;
  final int totalUniqueViewers;
  final int followerCount;
  final int watchlistCount;
  final List<EpisodeAnalytics> episodes;

  const SeriesAnalytics({
    required this.seriesId,
    required this.totalViews,
    required this.totalUniqueViewers,
    required this.followerCount,
    required this.watchlistCount,
    required this.episodes,
  });

  factory SeriesAnalytics.fromJson(Map<String, dynamic> json) => SeriesAnalytics(
        seriesId: json['series_id'] as String,
        totalViews: (json['total_views'] as num?)?.toInt() ?? 0,
        totalUniqueViewers: (json['total_unique_viewers'] as num?)?.toInt() ?? 0,
        followerCount: (json['follower_count'] as num?)?.toInt() ?? 0,
        watchlistCount: (json['watchlist_count'] as num?)?.toInt() ?? 0,
        episodes: ((json['episodes'] as List<dynamic>?) ?? const [])
            .map((e) => EpisodeAnalytics.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  /// The episode with the highest completion rate among episodes that
  /// have enough data to report one — used for the one growth-insight
  /// line this screen shows, and only when it's actually computable
  /// (see the screen's own "don't fabricate insights" reasoning).
  EpisodeAnalytics? get bestCompletionEpisode {
    final withData = episodes.where((e) => e.completionRate != null).toList();
    if (withData.isEmpty) return null;
    withData.sort((a, b) => b.completionRate!.compareTo(a.completionRate!));
    return withData.first;
  }
}
