import 'package:flutter/material.dart';
import '../../models/mission.dart';
import '../../services/coin_service.dart';
import '../../services/mission_service.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/mission_card.dart';
import '../../utils/coin_format.dart';
import 'creator_dashboard_screen.dart';
class MissionsScreen extends StatefulWidget {
  const MissionsScreen({super.key});

  @override
  State<MissionsScreen> createState() => _MissionsScreenState();
}

class _MissionsScreenState extends State<MissionsScreen> {
  List<Mission> _missions = [];
  bool _loading = true;
  bool _checkinBusy = false;
  String? _toast;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final userId = SupabaseService.currentUserId;
    if (userId == null) return;
    setState(() => _loading = true);
    final missions = await MissionService.getTodayMissions(userId);
    if (!mounted) return;
    setState(() {
      _missions = missions;
      _loading = false;
    });
  }

  void _showToast(String msg) {
    setState(() => _toast = msg);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _toast = null);
    });
  }

  Future<void> _checkin() async {
    final userId = SupabaseService.currentUserId;
    if (userId == null) return;
    setState(() => _checkinBusy = true);
    try {
      final result = await CoinService.claimDailyCheckin(userId);
      if (result['success'] == true) {
        _showToast('+${formatCoins(result['reward'])} coins! Streak: ${result['streak']} 🔥');
      } else {
        _showToast(result['message'] ?? 'Already checked in');
      }
    } finally {
      if (mounted) setState(() => _checkinBusy = false);
    }
  }

  Future<void> _claim(Mission m) async {
    final userId = SupabaseService.currentUserId;
    if (userId == null || m.userMissionId == null) return;
    final result = await MissionService.claimMission(
      userId: userId,
      userMissionId: m.userMissionId!,
    );
    if (result['success'] == true) {
      _showToast('+${formatCoins(result['reward'])} coins!');
      _load();
    } else {
      _showToast(result['message'] ?? 'Could not claim');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: const Text('Missions'),
        actions: [
          IconButton(
            icon: const Icon(Icons.insights_outlined),
            tooltip: 'Growth Dashboard',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CreatorDashboardScreen()),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          _loading
              ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
              : RefreshIndicator(
                  onRefresh: _load,
                  color: AppColors.primary,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: AppTheme.card(),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'DAILY CHECK-IN',
                              style: TextStyle(
                                fontSize: 11,
                                letterSpacing: 1.2,
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              'Come back every day to grow your streak and earn more coins.',
                              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: _checkinBusy ? null : _checkin,
                                child: _checkinBusy
                                    ? const SizedBox(
                                        height: 18,
                                        width: 18,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Text('Check In Today'),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Row(
                        children: [
                          Icon(Icons.star, size: 16, color: AppColors.coin),
                          SizedBox(width: 6),
                          Text(
                            'Creator Challenges',
                            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Bigger rewards for real creator work — these matter most.',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                      ),
                      const SizedBox(height: 12),
                      ..._missions
                          .where((m) => m.isCreatorChallenge)
                          .map((m) => MissionCard(mission: m, onClaim: () => _claim(m))),
                      const SizedBox(height: 16),
                      const Text(
                        'Quick Engagement',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Small, simple actions — small rewards by design.',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                      ),
                      const SizedBox(height: 12),
                      ..._missions
                          .where((m) => !m.isCreatorChallenge)
                          .map((m) => MissionCard(mission: m, onClaim: () => _claim(m))),
                    ],
                  ),
                ),
          if (_toast != null)
            Positioned(
              top: 20,
              left: 40,
              right: 40,
              child: Material(
                color: AppColors.secondary,
                borderRadius: BorderRadius.circular(30),
                elevation: 8,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Text(
                    _toast!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
