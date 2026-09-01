import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';

/// The single check every gated action (posting, coins, AI features,
/// social actions) runs before doing anything — keeps the "is this a
/// guest, and if so how do we ask them to upgrade" logic in one place
/// instead of duplicated across every screen that has a gated button.
class GuestGate {
  /// Returns true if the action should proceed. A signed-in (non-guest)
  /// user always gets true immediately with no UI. A guest sees an inline
  /// upgrade sheet; returns true only if they complete it there and then,
  /// so the caller can just go ahead with the original action on success.
  static Future<bool> allow(BuildContext context, {required String action}) async {
    if (!SupabaseService.isGuest) return true;
    final upgraded = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _UpgradeSheet(action: action),
    );
    return upgraded ?? false;
  }
}

class _UpgradeSheet extends StatefulWidget {
  final String action;
  const _UpgradeSheet({required this.action});

  @override
  State<_UpgradeSheet> createState() => _UpgradeSheetState();
}

class _UpgradeSheetState extends State<_UpgradeSheet> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _upgrade() async {
    if (_email.text.trim().isEmpty || _password.text.length < 6) {
      setState(() => _error = 'Enter an email and a password (6+ characters)');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await AuthService.upgradeToFullAccount(
        email: _email.text.trim(),
        password: _password.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _error = 'Could not create account: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.surfaceBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Create an account to ${widget.action}',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            const Text(
              "You're browsing as a guest — add an email and password and everything "
              "you've already done in this session carries over, nothing is lost.",
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(hintText: 'Email'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              obscureText: true,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(hintText: 'Password (min 6 characters)'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
            ],
            const SizedBox(height: 18),
            ElevatedButton(
              onPressed: _loading ? null : _upgrade,
              child: _loading
                  ? const SizedBox(
                      height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Create Account'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _loading ? null : () => Navigator.of(context).pop(false),
              child: const Text('Not now', style: TextStyle(color: AppColors.textMuted)),
            ),
          ],
        ),
      ),
    );
  }
}
