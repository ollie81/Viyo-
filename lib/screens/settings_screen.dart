import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import 'auth/login_screen.dart';
import 'invite_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _logout(BuildContext context) async {
    await AuthService.signOut();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
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
              onTap: () {},
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
