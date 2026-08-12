import 'package:flutter/material.dart';
import '../models/viyo_mission.dart';
import '../services/viyo_mission_router.dart';

class ViyoMissionCard extends StatelessWidget {
  final ViyoMission mission;
  final VoidCallback? onClaim;
  final ViyoMissionRouter router;

  const ViyoMissionCard({
    super.key,
    required this.mission,
    this.onClaim,
    this.router = const ViyoMissionRouter(),
  });

  @override
  Widget build(BuildContext context) {
    final ratio = mission.progressRatio;

    return Material(
      color: const Color(0xFF11141F),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: mission.completed
            ? null
            : () => router.openMission(context, mission),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF7E72FF), Color(0xFF38D6C4)],
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      mission.completed
                          ? Icons.check_rounded
                          : Icons.bolt_rounded,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          mission.title,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          mission.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                            height: 1.25,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _Reward(mission.rewardCoins),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: LinearProgressIndicator(
                        value: ratio,
                        minHeight: 7,
                        backgroundColor: Colors.white.withOpacity(.07),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${mission.progress}/${mission.target}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.white60,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: mission.completed
                      ? null
                      : mission.canClaim
                          ? onClaim
                          : () => router.openMission(context, mission),
                  child: Text(
                    mission.completed
                        ? 'Completed'
                        : mission.canClaim
                            ? 'Claim ${mission.rewardCoins} Coins'
                            : 'Do Mission',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Reward extends StatelessWidget {
  final int coins;
  const _Reward(this.coins);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFFFC857).withOpacity(.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: const Color(0xFFFFC857).withOpacity(.18),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.monetization_on_rounded,
              size: 14, color: Color(0xFFFFC857)),
          const SizedBox(width: 4),
          Text(
            '+$coins',
            style: const TextStyle(
              color: Color(0xFFFFD56B),
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}
