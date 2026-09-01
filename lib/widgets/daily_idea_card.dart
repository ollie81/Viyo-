import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/ai_service.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import 'guest_gate.dart';

/// A daily content-idea nudge on the Growth Dashboard. Reuses the
/// existing /content-ideas endpoint rather than needing new backend
/// infrastructure — the "daily" part is purely a local, once-per-
/// calendar-day cache, not a real push notification (this app has no
/// FCM/APNs setup). The point is still the same: give creators a
/// reason to open the app even on a day they haven't posted yet.
class DailyIdeaCard extends StatefulWidget {
  final String niche;

  const DailyIdeaCard({super.key, required this.niche});

  @override
  State<DailyIdeaCard> createState() => _DailyIdeaCardState();
}

class _DailyIdeaCardState extends State<DailyIdeaCard> {
  static const _dateKey = 'daily_idea_date';
  static const _ideasKey = 'daily_idea_list';

  List<String>? _ideas;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String get _today {
    final now = DateTime.now();
    return '${now.year}-${now.month}-${now.day}';
  }

  Future<void> _load({bool forceRefresh = false}) async {
    // Guests never trigger the OpenAI call at all — not just blocked at
    // the button, skipped entirely, since this fires automatically on
    // dashboard load and AI features are account-gated.
    if (SupabaseService.isGuest) {
      setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedDate = prefs.getString(_dateKey);
      final cachedIdeas = prefs.getStringList(_ideasKey);

      if (!forceRefresh && cachedDate == _today && cachedIdeas != null && cachedIdeas.isNotEmpty) {
        if (!mounted) return;
        setState(() {
          _ideas = cachedIdeas;
          _loading = false;
        });
        return;
      }

      final niche = widget.niche.trim().isEmpty ? 'content creation' : widget.niche;
      final ideas = await AiService.getContentIdeas(niche);
      final topIdeas = ideas.take(3).toList();

      await prefs.setString(_dateKey, _today);
      await prefs.setStringList(_ideasKey, topIdeas);

      if (!mounted) return;
      setState(() {
        _ideas = topIdeas;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = "Could not load today's ideas";
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppTheme.glowCard(glowColor: AppColors.primary, glowOpacity: 0.16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.wb_sunny_outlined, size: 16, color: AppColors.primary),
              const SizedBox(width: 6),
              const Text(
                'IDEA OF THE DAY',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 1.2,
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (!_loading && !SupabaseService.isGuest)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.refresh, size: 16, color: AppColors.textMuted),
                  tooltip: 'Get new ideas',
                  onPressed: () => _load(forceRefresh: true),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (SupabaseService.isGuest)
            GestureDetector(
              onTap: () async {
                if (await GuestGate.allow(context, action: 'get AI content ideas')) _load();
              },
              child: const Text(
                'Create an account to unlock daily AI content ideas',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12, decoration: TextDecoration.underline),
              ),
            )
          else if (_loading)
            const SizedBox(
              height: 40,
              child: Center(
                child: SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                ),
              ),
            )
          else if (_error != null)
            Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 12))
          else
            ...?_ideas?.map(
              (idea) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Icon(Icons.bolt, size: 14, color: AppColors.coin),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(idea, style: const TextStyle(fontSize: 13, height: 1.4)),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
