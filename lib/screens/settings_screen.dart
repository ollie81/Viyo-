import 'package:flutter/material.dart';
import '../../services/ai_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import 'auth/login_screen.dart';
import 'invite_screen.dart';
import 'privacy_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _deleting = false;

  Future<void> _logout(BuildContext context) async {
    await AuthService.signOut();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  Future<void> _confirmDeleteAccount(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete your account?'),
        content: const Text(
          'This permanently deletes your posts, Coach history, and profile, '
          'and signs you out for good. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    setState(() => _deleting = true);
    try {
      await AiService.deleteAccount();
      await AuthService.signOut();
      if (!context.mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
    } catch (e) {
      if (!context.mounted) return;
      setState(() => _deleting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete account: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: AppColors.background, title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _section([
            _tile(
              context,
              icon: Icons.card_giftcard,
              iconColor: AppColors.secondary,
              title: 'Invite Friends',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const InviteScreen()),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          _section([
            _tile(
              context,
              icon: Icons.notifications_outlined,
              title: 'Notification Preferences',
              onTap: () {},
            ),
            _divider(),
            _tile(
              context,
              icon: Icons.privacy_tip_outlined,
              title: 'Privacy',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PrivacyScreen()),
              ),
            ),
            _divider(),
            _tile(
              context,
              icon: Icons.help_outline,
              title: 'Help & Support',
              onTap: () {},
            ),
          ]),
          const SizedBox(height: 16),
          _section([
            _tile(
              context,
              icon: Icons.logout,
              iconColor: AppColors.danger,
              title: 'Log Out',
              titleColor: AppColors.danger,
              showChevron: false,
              onTap: () => _logout(context),
            ),
          ]),
          const SizedBox(height: 16),
          _section([
            _tile(
              context,
              icon: Icons.delete_forever_outlined,
              iconColor: AppColors.danger,
              title: _deleting ? 'Deleting account...' : 'Delete Account',
              titleColor: AppColors.danger,
              showChevron: false,
              onTap: _deleting ? () {} : () => _confirmDeleteAccount(context),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _section(List<Widget> children) {
    return Container(
      decoration: AppTheme.card(),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }

  Widget _divider() => const Divider(height: 1, color: AppColors.surfaceBorder);

  Widget _tile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    Color? iconColor,
    Color? titleColor,
    bool showChevron = true,
  }) {
    return ListTile(
      leading: Icon(icon, color: iconColor ?? AppColors.textSecondary),
      title: Text(title, style: TextStyle(color: titleColor)),
      trailing: showChevron
          ? const Icon(Icons.chevron_right, color: AppColors.textMuted)
          : null,
      onTap: onTap,
    );
  }
}
