import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Explains what Viyo actually does with a creator's data, in plain
/// language, and links to the one control that matters most: deleting it.
///
/// This is a starting draft reflecting what the code in this repo actually
/// does — it has not been reviewed by a lawyer and does not attempt to
/// cover every jurisdiction's requirements (GDPR/CCPA specifics, etc.).
/// Have counsel review before treating this as your real privacy policy.
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: AppColors.background, title: const Text('Privacy')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _section(
            'What Viyo stores',
            'Your profile, the posts you publish (captions, photos, and videos), '
                'likes and comments, and your conversations with the AI Coach for '
                'each video — including any score the Coach gives.',
          ),
          _section(
            'What gets sent to AI providers',
            'When you ask the AI Coach to analyze a photo, video, or caption, that '
                'content is sent to OpenAI to generate feedback. Coach conversations '
                'are also sent to OpenAI each time you continue them, so the Coach '
                'has context. OpenAI processes this content to return a response; '
                'Viyo does not control OpenAI\'s own retention of API requests.',
          ),
          _section(
            'Where it\'s stored',
            'Your account, posts, and Coach history are stored in Viyo\'s database '
                '(Supabase). This data is kept until you delete your account, at '
                'which point it is removed as described below.',
          ),
          _section(
            'What Viyo does not do',
            'Viyo does not sell your content or conversations to third parties, '
                'and does not use your uploaded photos or videos to train AI models.',
          ),
          _section(
            'Your right to delete',
            'You can permanently delete your account and the data described above '
                'at any time from Settings. This removes your Coach history, posts, '
                'and profile, and disables your login — it cannot be undone.',
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: AppTheme.card(),
            child: const Text(
              'Questions about your data? Reach out from Settings → Help & Support.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 6),
          Text(body, style: const TextStyle(color: AppColors.textSecondary, height: 1.5)),
        ],
      ),
    );
  }
}
