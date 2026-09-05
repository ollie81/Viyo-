import 'package:flutter/material.dart';
import '../models/mission.dart';
import '../services/mission_service.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../utils/coin_format.dart';
import '../widgets/guest_gate.dart';
import '../screens/mission_screen.dart';

/// A glance at today's missions right where creators already look every
/// day — the home feed — instead of only inside the separate Missions
/// tab most people forget to open. Missions already reset daily
/// server-side (MissionService.getTodayMissions); this just surfaces
/// that existing daily reset somewhere people will actually see it.
class TodayMissionsPreview extends StatefulWidget {
  const TodayMissionsPreview({super.key});

  @override
  State<TodayMissionsPreview> createState() => _TodayMissionsPreviewState();
}

class _TodayMissionsPreviewState extends State<TodayMissionsPreview> {
  List<Mission>? _missions;
  bool _claiming = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final userId = SupabaseService.currentUserId;
    if (userId == null) return;
    try {
      final missions = await MissionService.getTodayMissions(userId);
      if (mounted) setState(() => _missions = missions);
    } catch (_) {
      // A preview card failing silently beats breaking the home feed —
      // the full Missions tab still works as the source of truth.
      if (mounted) setState(() => _missions = const []);
    }
  }

  Future<void> _claim(Mission m) async {
    final userId = SupabaseService.currentUserId;
    if (userId == null || m.userMissionId == null || _claiming) return;
    if (!await GuestGate.allow(context, action: 'earn coins')) return;
    setState(() => _claiming = true);
    try {
      final result = await MissionService.claimMission(
        userId: userId,
        userMissionId: m.userMissionId!,
      );
      if (!mounted) return;
      if (result['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('+${formatCoins(result['reward'])} coins!')),
        );
      }
      await _load();
    } finally {
      if (mounted) setState(() => _claiming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final missions = _missions;
    if (missions == null) return const SizedBox.shrink();

    final unclaimed = missions.where((m) => !m.claimed).toList()
      ..sort((a, b) {
        // Completed-but-unclaimed first — those are free coins waiting,
        // the most satisfying thing to surface at a glance.
        if (a.completed != b.completed) return a.completed ? -1 : 1;
        return 0;
      });

    if (unclaimed.isEmpty) {
      if (missions.isEmpty) return const SizedBox.shrink();
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: AppTheme.card(),
        child: Row(
          children: const [
            Icon(Icons.celebration_outlined, color: AppColors.success, size: 20),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                "All of today's missions are done — new ones tomorrow.",
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }

    final preview = unclaimed.take(3).toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      decoration: AppTheme.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.flag_outlined, size: 16, color: AppColors.primary),
              const SizedBox(width: 6),
              const Text("Today's Missions", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const MissionsScreen()),
                ),
                style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero),
                child: const Text('View all', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (final m in preview) _missionRow(m),
        ],
      ),
    );
  }

  Widget _missionRow(Mission m) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(m.title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 3),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: m.progress,
                    minHeight: 4,
                    backgroundColor: AppColors.surfaceBorder,
                    color: m.completed ? AppColors.success : AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (m.completed)
            SizedBox(
              height: 28,
              child: ElevatedButton(
                onPressed: _claiming ? null : () => _claim(m),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: Size.zero,
                  backgroundColor: AppColors.success,
                ),
                child: Text('Claim ${formatCoins(m.coinReward)}', style: const TextStyle(fontSize: 11)),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.coin.withOpacity(0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.monetization_on, size: 11, color: AppColors.coin),
                  const SizedBox(width: 2),
                  Text(formatCoins(m.coinReward),
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.coin)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
