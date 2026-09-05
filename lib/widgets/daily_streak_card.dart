import 'package:flutter/material.dart';
import '../models/user_profile.dart';
import '../services/coin_service.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../utils/coin_format.dart';

/// Streak lengths that get a little extra celebration when hit. Purely a
/// UI moment — the actual coin reward for any given streak length is
/// decided server-side by the claim_daily_checkin RPC, never invented here.
const List<int> kStreakMilestones = [3, 7, 14, 30, 60, 100];

int _nextMilestone(int streak) {
  for (final m in kStreakMilestones) {
    if (streak < m) return m;
  }
  final last = kStreakMilestones.last;
  return last * ((streak ~/ last) + 1);
}

int _prevMilestone(int streak) {
  var prev = 0;
  for (final m in kStreakMilestones) {
    if (m > streak) break;
    prev = m;
  }
  return prev;
}

bool isCheckedInToday(DateTime? lastCheckin) {
  if (lastCheckin == null) return false;
  final now = DateTime.now();
  return lastCheckin.year == now.year &&
      lastCheckin.month == now.month &&
      lastCheckin.day == now.day;
}

/// A compact, actionable streak card — shown at the top of the home feed
/// (where creators already open the app every day) as well as the Growth
/// Dashboard, so keeping the streak alive is something people see and can
/// act on immediately, not just a number buried in a secondary screen.
class DailyStreakCard extends StatefulWidget {
  final UserProfile profile;
  final VoidCallback? onCheckedIn;
  const DailyStreakCard({super.key, required this.profile, this.onCheckedIn});

  @override
  State<DailyStreakCard> createState() => _DailyStreakCardState();
}

class _DailyStreakCardState extends State<DailyStreakCard> {
  bool _busy = false;
  late bool _checkedInToday = isCheckedInToday(widget.profile.lastCheckinDate);
  late int _streak = widget.profile.currentStreak;

  Future<void> _checkIn() async {
    final userId = SupabaseService.currentUserId;
    if (userId == null || _busy || _checkedInToday) return;
    setState(() => _busy = true);
    try {
      final result = await CoinService.claimDailyCheckin(userId);
      if (!mounted) return;
      if (result['success'] == true) {
        final newStreak = (result['streak'] as num?)?.toInt() ?? _streak + 1;
        final milestone = kStreakMilestones.contains(newStreak);
        setState(() {
          _checkedInToday = true;
          _streak = newStreak;
        });
        widget.onCheckedIn?.call();
        _showCheckinToast(reward: result['reward'] as num?, streak: newStreak, milestone: milestone);
      } else {
        setState(() => _checkedInToday = true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showCheckinToast({num? reward, required int streak, required bool milestone}) {
    final rewardText = reward != null ? '+${formatCoins(reward)} coins' : 'Checked in';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: milestone ? AppColors.coin : AppColors.surface,
        content: Text(
          milestone
              ? '🔥 $streak-day streak! $rewardText — milestone bonus!'
              : '$rewardText · $streak-day streak',
          style: TextStyle(
            color: milestone ? AppColors.background : AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final next = _nextMilestone(_streak);
    final prev = _prevMilestone(_streak);
    final span = (next - prev).clamp(1, 1 << 30);
    final progress = ((_streak - prev) / span).clamp(0.0, 1.0);
    final daysLeft = next - _streak;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.card(borderColor: AppColors.coin.withOpacity(0.35)),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: AppColors.coin.withOpacity(0.15), shape: BoxShape.circle),
            child: const Icon(Icons.local_fire_department, color: AppColors.coin, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _streak == 0 ? 'Start a streak today' : '$_streak-day streak',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 5,
                    backgroundColor: AppColors.surfaceBorder,
                    color: AppColors.coin,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$daysLeft day${daysLeft == 1 ? '' : 's'} to your $next-day bonus',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _checkedInToday
              ? const Icon(Icons.check_circle, color: AppColors.success, size: 28)
              : ElevatedButton(
                  onPressed: _busy ? null : _checkIn,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    minimumSize: Size.zero,
                  ),
                  child: _busy
                      ? const SizedBox(
                          height: 14,
                          width: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.background),
                        )
                      : const Text('Check in', style: TextStyle(fontSize: 12)),
                ),
        ],
      ),
    );
  }
}
