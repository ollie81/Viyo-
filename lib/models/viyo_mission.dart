enum ViyoMissionAction {
  watchVideos,
  followCreator,
  likePosts,
  createPost,
  completeProfile,
  dailyCheckIn,
}

class ViyoMission {
  final String id;
  final String title;
  final String description;
  final int rewardCoins;
  final int target;
  final int progress;
  final ViyoMissionAction action;
  final bool completed;

  const ViyoMission({
    required this.id,
    required this.title,
    required this.description,
    required this.rewardCoins,
    required this.target,
    required this.progress,
    required this.action,
    this.completed = false,
  });

  double get progressRatio {
    if (target <= 0) return 0;
    final value = progress / target;
    return value.clamp(0.0, 1.0);
  }

  bool get canClaim => progress >= target && !completed;
}
