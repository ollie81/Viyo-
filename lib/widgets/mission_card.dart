// Viyo mission action safety: completion/rewards must be verified server-side.
import 'package:flutter/material.dart';
import '../models/mission.dart';
import '../theme/app_theme.dart';
import 'coin_badge.dart';

class MissionCard extends StatelessWidget {
  final Mission mission;
  final VoidCallback? onClaim;

  /// Called when the creator taps "Do Mission" (not started) or
  /// "Continue" (in progress). Routes them to the real screen that
  /// completes the mission — never just shows a toast.
  final VoidCallback? onAction;

  const MissionCard({
    super.key,
    required this.mission,
    this.onClaim,
    this.onAction,
  });

  String get _buttonLabel {
    if (mission.claimed) return 'Done ✓';
    if (mission.completed) return 'Claim';
    if (mission.progressCount > 0) return 'Continue';
    return 'Do Mission';
  }

  VoidCallback? get _buttonCallback {
    if (mission.claimed) return null;
    if (mission.completed && !mission.claimed) return onClaim;
    return onAction; // "Do Mission" or "Continue"
  }

  Color get _buttonColor {
    if (mission.claimed) return Colors.white12;
    if (mission.completed && !mission.claimed) return AppColors.primary;
    return AppColors.secondary;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: AppTheme.card(
        borderColor: mission.completed && !mission.claimed
            ? AppColors.primary.withOpacity(0.5)
            : null,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  mission.title,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: mission.claimed
                        ? AppColors.textSecondary
                        : AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  mission.description,
                  style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: mission.progress),
                    duration: const Duration(milliseconds: 700),
                    curve: Curves.easeOutCubic,
                    builder: (context, value, _) => LinearProgressIndicator(
                      value: value,
                      backgroundColor: Colors.white10,
                      color: mission.claimed ? Colors.white24 : AppColors.primary,
                      minHeight: 5,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    CoinBadge(amount: mission.coinReward, fontSize: 12),
                    const Spacer(),
                    Text(
                      '${mission.progressCount}/${mission.targetCount}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: _buttonCallback,
            style: ElevatedButton.styleFrom(
              backgroundColor: _buttonColor,
              foregroundColor: mission.claimed ? Colors.white38 : AppColors.background,
              disabledBackgroundColor: Colors.white12,
              disabledForegroundColor: Colors.white38,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
            child: Text(_buttonLabel, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
