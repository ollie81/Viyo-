import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';

/// How to report content you believe infringes your copyright, and what
/// a valid notice needs to include — the other side of the "creators
/// bring their own creations" upload model: Viyo doesn't verify what a
/// creator uploads actually belongs to them, so this notice-and-
/// takedown path is what stands in for that.
///
/// This is a starting draft reflecting standard DMCA notice-and-takedown
/// practice — it has not been reviewed by a lawyer, and publishing a
/// working process here is not the same as registering a DMCA agent
/// with the U.S. Copyright Office, which is a separate step the app's
/// operator needs to take for full safe-harbor protection. Have counsel
/// review before relying on this as your actual legal process.
class CopyrightScreen extends StatelessWidget {
  const CopyrightScreen({super.key});

  static const _contactEmail = 'olli1234x@gmail.com';

  Future<void> _emailUs(BuildContext context) async {
    final uri = Uri(
      scheme: 'mailto',
      path: _contactEmail,
      query: 'subject=${Uri.encodeComponent('Copyright takedown request — Viyo')}',
    );
    final opened = await launchUrl(uri);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Email us at $_contactEmail')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: AppColors.background, title: const Text('Copyright')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _section(
            'If your work was posted without permission',
            'Viyo lets creators upload their own video content, including to AI '
                'Short Drama series. If you believe something posted on Viyo '
                'infringes a copyright you own, you can ask us to remove it.',
          ),
          _section(
            'What to include in your request',
            '• A description of the copyrighted work you believe was infringed\n'
                '• A link to (or enough detail to find) the specific post or '
                'episode on Viyo\n'
                '• Your name and contact information\n'
                '• A statement that you have a good-faith belief the use isn\'t '
                'authorized by you, the copyright owner, or the law\n'
                '• A statement, made under penalty of perjury, that the above '
                'information is accurate and that you\'re the copyright owner or '
                'authorized to act on their behalf\n'
                '• Your physical or electronic signature',
          ),
          _section(
            'What happens next',
            'We review each request and remove content that appears to '
                'infringe. The creator who posted it may be notified and, for '
                'repeat or clear-cut infringement, may have their account '
                'suspended. If you believe your own content was removed by '
                'mistake, you can reply to the same email to request it be '
                'reinstated.',
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: AppTheme.glowCard(glowColor: AppColors.secondary, glowOpacity: 0.14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Send a takedown request',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
                const SizedBox(height: 6),
                Text(
                  _contactEmail,
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _emailUs(context),
                    icon: const Icon(Icons.email_outlined, size: 18),
                    label: const Text('Email Us'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'You can also report an individual post directly from its ••• menu '
            'and choose "Copyright infringement" as the reason — that reaches '
            'the same review process.',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.4),
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
