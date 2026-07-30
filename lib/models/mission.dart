import '../../widgets/mission_card.dart'; // This should work if mission_screen.dart is in lib/screens/
class Mission {
  final String id;
  final String code;
  final String title;
  final String description;
  final double coinReward;
  final int targetCount;
  final String category; // 'engagement' | 'creator_challenge' | 'checkin'

  // From user_missions join for "today"
  final int progressCount;
  final bool completed;
  final bool claimed;
  final String? userMissionId; // id of the user_missions row, needed to claim

  Mission({
    required this.id,
    required this.code,
    required this.title,
    required this.description,
    required this.coinReward,
    required this.targetCount,
    this.category = 'engagement',
    this.progressCount = 0,
    this.completed = false,
    this.claimed = false,
    this.userMissionId,
  });

  factory Mission.fromJson(Map<String, dynamic> json) => Mission(
        id: json['id'],
        code: json['code'],
        title: json['title'],
        description: json['description'],
        coinReward: (json['coin_reward'] as num).toDouble(),
        targetCount: json['target_count'] ?? 1,
        category: json['category'] ?? 'engagement',
        progressCount: json['progress_count'] ?? 0,
        completed: json['completed'] ?? false,
        claimed: json['claimed'] ?? false,
        userMissionId: json['_user_mission_id'],
      );

  bool get isCreatorChallenge => category == 'creator_challenge';

  double get progress =>
      targetCount == 0 ? 0 : (progressCount / targetCount).clamp(0, 1);
}
