import 'package:flutter/material.dart';
import '../models/trending_result.dart';
import '../services/ai_service.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import 'guest_gate.dart';

/// "What's working right now in your niche" — the only trend signal
/// this app can honestly offer without a TikTok/Instagram/YouTube
/// integration: aggregated, anonymous engagement from other creators
/// in the same niche on this app.
class TrendingCard extends StatefulWidget {
  final String niche;

  const TrendingCard({super.key, required this.niche});

  @override
  State<TrendingCard> createState() => _TrendingCardState();
}

class _TrendingCardState extends State<TrendingCard> {
  TrendingResult? _result;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant TrendingCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.niche != widget.niche) _load();
  }

  Future<void> _load() async {
    if (widget.niche.trim().isEmpty) {
      setState(() {
        _loading = false;
        _failed = true;
      });
      return;
    }
    // Guests never trigger the request at all — this fires automatically
    // on dashboard load, and AI features are account-gated.
    if (SupabaseService.isGuest) {
      setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final result = await AiService.getTrending(widget.niche);
      if (!mounted) return;
      setState(() {
        _result = result;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Quietly disappears on failure, no niche, or too little data in
    // this niche yet — a "not enough data" card would just be noise
    // for a niche with few creators posting. Guests are the one
    // exception: still show the card shell so the upgrade teaser below
    // has somewhere to appear, instead of vanishing along with real
    // "no data" cases.
    if (!SupabaseService.isGuest && (_failed || (!_loading && _result?.hasData != true))) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppTheme.glowCard(glowColor: AppColors.secondary, glowOpacity: 0.16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.local_fire_department_outlined, size: 16, color: AppColors.secondary),
              const SizedBox(width: 6),
              Text(
                'TRENDING IN ${widget.niche.toUpperCase()}',
                style: const TextStyle(
                  fontSize: 11,
                  letterSpacing: 1.0,
                  color: AppColors.secondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (SupabaseService.isGuest)
            GestureDetector(
              onTap: () async {
                if (await GuestGate.allow(context, action: 'see trending ideas')) _load();
              },
              child: const Text(
                'Create an account to see what\'s trending in your niche',
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
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.secondary),
                ),
              ),
            )
          else ...[
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _result!.themes
                  .map(
                    (theme) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.secondary.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        theme,
                        style: const TextStyle(fontSize: 12, color: AppColors.secondary, fontWeight: FontWeight.w600),
                      ),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 12),
            Text(
              _result!.idea,
              style: const TextStyle(fontSize: 13, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }
}
