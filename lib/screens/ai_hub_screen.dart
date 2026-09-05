import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'creator_dashboard_screen.dart';
import 'post/ai_repurpose_screen.dart';
import 'post/create_post_screen.dart';
import 'profile/profile_screen.dart';

/// A single showcase of every AI feature in the app. These features are
/// Viyo's real differentiator (see the coin-gating + "Why This Worked"
/// work) but were scattered across five different screens with no one
/// place that says "here's everything your AI Coach can do" — this is
/// that place, and the entry point creators actually see every day
/// (feed_screen.dart's app bar) points straight at it.
class AiHubScreen extends StatelessWidget {
  const AiHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: const Text('AI Tools'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: AppTheme.glowCard(glowColor: AppColors.secondary, gradient: AppGradients.primary),
            child: const Row(
              children: [
                Icon(Icons.auto_awesome, color: AppColors.secondary, size: 26),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    "Your AI Coach — everything it can do for you, in one place",
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, height: 1.3),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          _SectionHeader('Before You Post'),
          _FeatureCard(
            icon: Icons.bolt,
            iconColor: AppColors.primary,
            title: 'Hook Check',
            description: "Get instant AI feedback on your caption's opening line — the part that decides whether anyone keeps reading.",
            costLabel: '5 coins · 1 free/day',
            onTap: () => _open(context, const CreatePostScreen()),
          ),
          _FeatureCard(
            icon: Icons.lightbulb_outline,
            iconColor: AppColors.coin,
            title: 'Caption Ideas',
            description: 'Three caption variants generated from a rough idea — tailored to your own best-performing style once you have post history.',
            costLabel: '5 coins · 1 free/day',
            onTap: () => _open(context, const CreatePostScreen()),
          ),
          _FeatureCard(
            icon: Icons.auto_fix_high,
            iconColor: AppColors.secondary,
            title: 'Improve with AI',
            description: 'Polishes the wording and flow of a caption you already wrote.',
            costLabel: '5 coins · 1 free/day',
            onTap: () => _open(context, const CreatePostScreen()),
          ),

          const SizedBox(height: 22),
          _SectionHeader('After You Post'),
          _FeatureCard(
            icon: Icons.insights,
            iconColor: AppColors.success,
            title: 'Why This Worked',
            description: "A plain-language explanation of how one of your posts performed, grounded in your own real numbers — never a made-up reach or algorithm claim.",
            costLabel: '5 coins · 1 free/day',
            onTap: () => _open(context, const ProfileScreen()),
            hint: 'Open one of your posts, then tap "Why This Worked".',
          ),
          const _FeatureCard(
            icon: Icons.record_voice_over,
            iconColor: AppColors.primary,
            title: 'Voice Consistency Check',
            description: "Runs automatically as you post — flags a caption that reads off-brand from everything else you've written, with a rewrite in your own voice.",
            costLabel: 'Automatic · Free',
          ),

          const SizedBox(height: 22),
          _SectionHeader('Grow Faster'),
          _FeatureCard(
            icon: Icons.movie_creation_outlined,
            iconColor: AppColors.secondary,
            title: 'AI Repurposer',
            description: 'Upload one longer video — get back up to 3 ranked highlight clips, auto-cropped with burned-in captions and dead air trimmed out.',
            costLabel: '40 coins',
            onTap: () => _open(context, const AiRepurposeScreen()),
          ),
          _FeatureCard(
            icon: Icons.chat_bubble_outline,
            iconColor: AppColors.coin,
            title: 'AI Video Coach',
            description: 'A persistent AI conversation about one specific video — what worked, what to fix, what to try next.',
            costLabel: '10 coins/message · 1 free/day',
            onTap: () => _open(context, const AiRepurposeScreen()),
            hint: 'Run the AI Repurposer first, then tap "Open AI Coach" on a clip.',
          ),

          const SizedBox(height: 22),
          _SectionHeader('Your Growth Dashboard'),
          _FeatureCard(
            icon: Icons.dashboard_customize_outlined,
            iconColor: AppColors.primary,
            title: 'Weekly Report, Trends & Ideas',
            description: 'Your weekly Coach report card, fresh content ideas for your niche, and what\'s trending on Viyo right now — all automatic, all free.',
            costLabel: 'Automatic · Free',
            onTap: () => _open(context, const CreatorDashboardScreen()),
          ),
        ],
      ),
    );
  }

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.0,
          color: AppColors.textMuted,
        ),
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String description;
  final String costLabel;
  final VoidCallback? onTap;
  final String? hint;

  const _FeatureCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.description,
    required this.costLabel,
    this.onTap,
    this.hint,
  });

  bool get _isFree => costLabel.toLowerCase().contains('free') && !costLabel.contains('/day');

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: AppTheme.card(),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: iconColor.withOpacity(0.14), borderRadius: BorderRadius.circular(12)),
                  child: Icon(icon, color: iconColor, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: (_isFree ? AppColors.success : AppColors.coin).withOpacity(0.14),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              costLabel,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: _isFree ? AppColors.success : AppColors.coin,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(description, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.4)),
                      if (hint != null) ...[
                        const SizedBox(height: 6),
                        Text(hint!, style: const TextStyle(color: AppColors.textMuted, fontSize: 11, fontStyle: FontStyle.italic)),
                      ],
                      if (onTap != null) ...[
                        const SizedBox(height: 8),
                        const Row(
                          children: [
                            Text('Try it', style: TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w600)),
                            SizedBox(width: 3),
                            Icon(Icons.arrow_forward, size: 12, color: AppColors.primary),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
