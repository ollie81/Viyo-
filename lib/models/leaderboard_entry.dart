class LeaderboardEntry {
  final String userId;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final int coinsEarned;
  final int rank;

  LeaderboardEntry({
    required this.userId,
    required this.username,
    required this.displayName,
    this.avatarUrl,
    required this.coinsEarned,
    required this.rank,
  });

  factory LeaderboardEntry.fromJson(Map<String, dynamic> json) => LeaderboardEntry(
        userId: json['user_id'] as String,
        username: json['username'] as String? ?? '',
        displayName: json['display_name'] as String? ?? '',
        avatarUrl: json['avatar_url'] as String?,
        coinsEarned: (json['coins_earned'] as num?)?.toInt() ?? 0,
        rank: (json['rank'] as num?)?.toInt() ?? 0,
      );
}

class WeeklyLeaderboard {
  final List<LeaderboardEntry> entries;
  final int? myRank;
  final int? myCoinsEarned;
  final int windowDays;

  WeeklyLeaderboard({
    required this.entries,
    this.myRank,
    this.myCoinsEarned,
    required this.windowDays,
  });

  factory WeeklyLeaderboard.fromJson(Map<String, dynamic> json) => WeeklyLeaderboard(
        entries: (json['entries'] as List? ?? [])
            .map((e) => LeaderboardEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
        myRank: (json['my_rank'] as num?)?.toInt(),
        myCoinsEarned: (json['my_coins_earned'] as num?)?.toInt(),
        windowDays: (json['window_days'] as num?)?.toInt() ?? 7,
      );
}
