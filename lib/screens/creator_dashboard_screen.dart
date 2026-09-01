
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../models/creator_stats.dart';
import '../models/user_profile.dart';
import '../services/profile_service.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/coin_badge.dart';
import '../widgets/daily_idea_card.dart';

/// The Creator Growth Dashboard — one place to see performance,
/// progress, level, achievements, and a nudge toward the AI Coach.
/// This is the "am I actually getting better?" screen, which is the
/// core promise behind "Viyo helps creators grow, not just chase views."
class CreatorDashboardScreen extends StatefulWidget {
  const CreatorDashboardScreen({super.key});

  @override
  State<CreatorDashboardScreen> createState() => _CreatorDashboardScreenState();
}

class _CreatorDashboardScreenState extends State<CreatorDashboardScreen> {
  UserProfile? _profile;
  CreatorStats? _stats;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final userId = SupabaseService.currentUserId;
    if (userId == null) return;
    setState(() => _loading = true);
    final profile = await ProfileService.getProfile(userId);
    final stats = await ProfileService.getCreatorStats(userId);
    if (!mounted) return;
    setState(() {
      _profile = profile;
      _stats = stats;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _profile == null || _stats == null) {
      return Scaffold(
        appBar: AppBar(backgroundColor: AppColors.background, title: const Text('Growth Dashboard')),
        body: const _DashboardSkeleton(),
      );
    }

    final p = _profile!;
    final s = _stats!;

    return Scaffold(
      appBar: AppBar(backgroundColor: AppColors.background, title: const Text('Growth Dashboard')),
      body: RefreshIndicator(
        onRefresh: _load,
        color: AppColors.primary,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Level / rank progress
            Container(
              padding: const EdgeInsets.all(20),
              decoration: AppTheme.glowCard(
                glowColor: AppColors.secondary,
                gradient: AppGradients.primary,
                glowOpacity: 0.18,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${p.rank} · Level ${p.level}',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 2),
                          Text('${p.xp} XP total',
                              style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                        ],
                      ),
                      CoinBadge(amount: p.pointsBalance, fontSize: 18),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: p.levelProgress),
                      duration: const Duration(milliseconds: 900),
                      curve: Curves.easeOutCubic,
                      builder: (context, value, _) => LinearProgressIndicator(
                        value: value,
                        backgroundColor: Colors.white10,
                        color: AppColors.secondary,
                        minHeight: 6,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${p.xp % p.xpForNextLevel} / ${p.xpForNextLevel} XP to Level ${p.level + 1}',
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            DailyIdeaCard(niche: p.niche),
            const SizedBox(height: 16),

            // Growth performance grid
            const Text('Performance', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            const SizedBox(height: 10),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.6,
              children: [
                _statCard('Posts (30d)', '${s.postsLast30Days}', Icons.grid_view_rounded, AppColors.primary),
                _statCard('Total Posts', '${s.totalPosts}', Icons.dashboard_customize_outlined, AppColors.secondary),
                _statCard('Likes Received', '${s.totalLikesReceived}', Icons.favorite, AppColors.secondary),
                _statCard('Comments Received', '${s.totalCommentsReceived}', Icons.mode_comment, AppColors.primary),
                _statCard('Followers', '${s.followers}', Icons.people_outline, AppColors.coin),
                _statCard('Missions Done (30d)', '${s.missionsCompleted30Days}', Icons.flag, AppColors.success),
              ],
            ),
            const SizedBox(height: 20),

            // Streak
            Container(
              padding: const EdgeInsets.all(16),
              decoration: AppTheme.card(),
              child: Row(
                children: [
                  const Icon(Icons.local_fire_department, color: AppColors.coin, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${p.currentStreak}-day streak',
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text('Longest: ${p.longestStreak} days',
                            style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // AI Coach nudge — the differentiating feature, so it should
            // visually stand out rather than look like another stat card.
            Container(
              padding: const EdgeInsets.all(20),
              decoration: AppTheme.glowCard(glowColor: AppColors.secondary),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.auto_awesome, size: 16, color: AppColors.secondary),
                      SizedBox(width: 6),
                      Text(
                        'AI CREATOR COACH',
                        style: TextStyle(
                          fontSize: 11,
                          letterSpacing: 1.2,
                          color: AppColors.secondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    s.aiFeedbackCount == 0
                        ? "You haven't gotten coaching feedback yet — post something and your coach will review it right after."
                        : "Your coach has reviewed ${s.aiFeedbackCount} of your posts. Keep posting to keep improving.",
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withOpacity(0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 17),
          ),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
        ],
      ),
    );
  }
}

/// Skeleton shown while the dashboard's profile/stats are loading — mimics
/// the real layout instead of a bare spinner, so the screen doesn't "pop"
/// once data arrives.
class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppColors.surface,
      highlightColor: AppColors.surfaceBorder,
      child: ListView(
        padding: const EdgeInsets.all(16),
        physics: const NeverScrollableScrollPhysics(),
        children: [
          _block(height: 128),
          const SizedBox(height: 16),
          _block(height: 16, width: 100),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.6,
            children: List.generate(6, (_) => _block()),
          ),
          const SizedBox(height: 20),
          _block(height: 64),
          const SizedBox(height: 20),
          _block(height: 110),
        ],
      ),
    );
  }

  Widget _block({double height = 80, double? width}) => Container(
        height: height,
        width: width,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
      );
}
