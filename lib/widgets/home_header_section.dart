import 'package:flutter/material.dart';
import '../models/user_profile.dart';
import '../services/profile_service.dart';
import '../services/supabase_service.dart';
import 'daily_streak_card.dart';
import 'today_missions_preview.dart';

/// Sits at the top of the home feed — the one screen creators already
/// open every day — surfacing the two things that reset daily
/// (check-in streak, today's missions) so they're a glance away instead
/// of buried in the separate Dashboard/Missions tabs. Loads its own
/// profile so feed_screen.dart doesn't need to know about either
/// feature; fails silently (collapses to nothing) rather than risk
/// breaking the feed underneath it.
class HomeHeaderSection extends StatefulWidget {
  const HomeHeaderSection({super.key});

  @override
  State<HomeHeaderSection> createState() => _HomeHeaderSectionState();
}

class _HomeHeaderSectionState extends State<HomeHeaderSection> {
  UserProfile? _profile;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final userId = SupabaseService.currentUserId;
    if (userId == null) return;
    try {
      final profile = await ProfileService.getProfile(userId);
      if (mounted) setState(() => _profile = profile);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_failed || _profile == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DailyStreakCard(profile: _profile!, onCheckedIn: _load),
          const SizedBox(height: 12),
          const TodayMissionsPreview(),
        ],
      ),
    );
  }
}
