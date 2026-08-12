import 'package:flutter/material.dart';
import '../../models/post_feedback.dart';
import '../../theme/app_theme.dart';

/// Shown immediately after a creator posts — the "personal coach"
/// moment. Framed entirely as encouragement + growth, never a score,
/// so it reinforces "Viyo helps you get better" rather than judging
/// the post.
class CoachFeedbackScreen extends StatelessWidget {
  final PostFeedback feedback;
  const CoachFeedbackScreen({super.key, required this.feedback});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: const Text('Your Coach Says...'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Row(
            children: const [
              Icon(Icons.auto_awesome, color: AppColors.secondary, size: 22),
              SizedBox(width: 8),
              Text(
                'AI Creator Coach',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Personal feedback to help you grow — not a score.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 20),

          _section(
            icon: Icons.thumb_up_alt_outlined,
            iconColor: AppColors.success,
            title: 'What worked',
            body: feedback.whatWorked,
          ),
          const SizedBox(height: 12),
          _section(
            icon: Icons.trending_up,
            iconColor: AppColors.primary,
            title: 'One thing to improve',
            body: feedback.whatToImprove,
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: AppTheme.card(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: const [
                    Icon(Icons.lightbulb_outline, size: 18, color: AppColors.coin),
                    SizedBox(width: 8),
                    Text('Ideas for next time', style: TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 10),
                ...feedback.contentIdeas.map(
                  (idea) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('• ', style: TextStyle(color: AppColors.coin)),
                        Expanded(child: Text(idea, style: const TextStyle(height: 1.3))),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _section(
            icon: Icons.people_outline,
            iconColor: AppColors.secondary,
            title: 'Boost engagement',
            body: feedback.engagementTip,
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Got it, thanks!'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String body,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: iconColor),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 8),
          Text(body, style: const TextStyle(height: 1.4)),
        ],
      ),
    );
  }
}
