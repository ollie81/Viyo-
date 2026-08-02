class UserProfile {
  final String id;
  final String username;
  final String displayName;
  final String bio;
  final String? avatarUrl;
  final String niche;

  final double pointsBalance;
  final int xp;
  final int level;
  final String rank;

  final int currentStreak;
  final int longestStreak;
  final DateTime? lastCheckinDate;

  final String referralCode;
  final bool isPremium;

  UserProfile({
    required this.id,
    required this.username,
    required this.displayName,
    this.bio = '',
    this.avatarUrl,
    this.niche = '',
    this.pointsBalance = 0,
    this.xp = 0,
    this.level = 1,
    this.rank = 'Bronze',
    this.currentStreak = 0,
    this.longestStreak = 0,
    this.lastCheckinDate,
    required this.referralCode,
    this.isPremium = false,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        id: json['id'],
        username: json['username'],
        displayName: json['display_name'],
        bio: json['bio'] ?? '',
        avatarUrl: json['avatar_url'],
        niche: json['niche'] ?? '',
        pointsBalance: (json['points_balance'] as num?)?.toDouble() ?? 0,
        xp: json['xp'] ?? 0,
        level: json['level'] ?? 1,
        rank: json['rank'] ?? 'Bronze',
        currentStreak: json['current_streak'] ?? 0,
        longestStreak: json['longest_streak'] ?? 0,
        lastCheckinDate: json['last_checkin_date'] != null
            ? DateTime.tryParse(json['last_checkin_date'])
            : null,
        referralCode: json['referral_code'] ?? '',
        isPremium: json['is_premium'] ?? false,
      );

  /// XP required to reach the *next* level, using a simple curve.
  /// Tune this once real engagement data comes in.
  int get xpForNextLevel => 100 * level;

  double get levelProgress {
    final needed = xpForNextLevel;
    if (needed == 0) return 0;
    return (xp % needed) / needed;
  }

  static String rankForLevel(int level) {
    if (level <= 5) return 'Bronze';
    if (level <= 15) return 'Silver';
    if (level <= 30) return 'Gold';
    if (level <= 50) return 'Platinum';
    return 'Diamond';
  }
}



