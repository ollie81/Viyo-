import 'package:flutter/material.dart';
import '../models/mission.dart';
import '../theme/app_theme.dart';
import 'coin_badge.dart';

class MissionCard extends StatelessWidget {
  final Mission mission;
  final VoidCallback? onClaim;

  const MissionCard({super.key, required this.mission, this.onClaim});
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
                  child: LinearProgressIndicator(
                    value: mission.progress,
                    backgroundColor: Colors.white10,
                    color: AppColors.primary,
                    minHeight: 5,
                  ),
                ),
                const SizedBox(height: 6),
                CoinBadge(amount: mission.coinReward, fontSize: 12),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: (mission.completed && !mission.claimed) ? onClaim : null,
            style: ElevatedButton.styleFrom(
              disabledBackgroundColor: Colors.white12,
              disabledForegroundColor: Colors.white38,
            ),
            child: Text(
              mission.claimed
                  ? 'Done ✓'
                  : mission.completed
                      ? 'Claim'
                      : '${mission.progressCount}/${mission.targetCount}',
            ),
          ),
        ],
      ),
    );
  }
}

