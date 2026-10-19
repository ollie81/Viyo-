import 'package:flutter/material.dart';
import '../models/user_profile.dart';
import '../services/profile_service.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/daily_idea_card.dart';
import '../widgets/trending_card.dart';

/// The "Creator Feed" — a dedicated destination for the AI-generated
/// trend/idea signal that used to live buried inside the Growth
/// Dashboard (TrendingCard/DailyIdeaCard). Deliberately NOT a new
/// bottom-nav tab — see ViyoGlassBottomNav's own comment on why the
/// nav is kept at a fixed 5 tabs — so this is reached the same way
/// Missions already is: a button from an existing screen (here, the
/// Dashboard) rather than a new permanent slot.
///
/// Both cards are real, already-working AI calls (TrendingCard reads
/// real aggregated engagement from other creators in the same niche;
/// DailyIdeaCard calls the existing /content-ideas endpoint) — this
/// screen is a composition/navigation change, not new AI backend work.
class CreatorFeedScreen extends StatefulWidget {
  const CreatorFeedScreen({super.key});

  @override
  State<CreatorFeedScreen> createState() => _CreatorFeedScreenState();
}

class _CreatorFeedScreenState extends State<CreatorFeedScreen> {
  UserProfile? _profile;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final userId = SupabaseService.currentUserId;
    if (userId == null) {
      setState(() => _loading = false);
      return;
    }
    final profile = await ProfileService.getProfile(userId);
    if (!mounted) return;
    setState(() {
      _profile = profile;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final niche = _profile?.niche ?? '';
    return Scaffold(
      appBar: AppBar(backgroundColor: AppColors.background, title: const Text('Creator Feed')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              color: AppColors.primary,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text(
                    'What\'s working right now, and what to make next — pulled from real engagement '
                    'on this app, not guesswork.',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12.5, height: 1.4),
                  ),
                  const SizedBox(height: 16),
                  TrendingCard(niche: niche),
                  const SizedBox(height: 16),
                  DailyIdeaCard(niche: niche),
                ],
              ),
            ),
    );
  }
}
