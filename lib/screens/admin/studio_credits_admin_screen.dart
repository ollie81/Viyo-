import 'package:flutter/material.dart';

import '../../services/creator_studio_service.dart';
import '../../theme/app_theme.dart';
import '../studio/studio_widgets.dart';

/// Admin: add Studio credits to an account, either free (promotional) or
/// for a payment received outside the app (mobile money, PayPal) until card
/// checkout is switched on. The admin key is kept in memory only.
class StudioCreditsAdminScreen extends StatefulWidget {
  const StudioCreditsAdminScreen({super.key});
  @override
  State<StudioCreditsAdminScreen> createState() => _StudioCreditsAdminScreenState();
}

class _StudioCreditsAdminScreenState extends State<StudioCreditsAdminScreen> {
  final _key = TextEditingController();
  final _user = TextEditingController();
  final _credits = TextEditingController(text: '500');
  final _amount = TextEditingController();
  final _reference = TextEditingController();
  final _note = TextEditingController();
  String _kind = 'purchase';
  bool _sending = false;
  String? _result;
  bool _ok = false;

  @override
  void dispose() {
    for (final c in [_key, _user, _credits, _amount, _reference, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _send() async {
    final credits = int.tryParse(_credits.text.trim()) ?? 0;
    if (_key.text.trim().isEmpty || _user.text.trim().isEmpty || credits <= 0) {
      setState(() {
        _ok = false;
        _result = 'Fill in the admin key, the user and a number of credits.';
      });
      return;
    }
    if (_kind == 'purchase' && _reference.text.trim().isEmpty) {
      setState(() {
        _ok = false;
        _result = 'Add the payment reference (e.g. the MoMo transaction ID) so it can never be added twice.';
      });
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: StudioColors.panel,
        title: const Text('Add credits?'),
        content: Text('${creditsLabel(credits)} (${_kind == 'purchase' ? 'paid' : 'free, promotional'}) to ${_user.text.trim()}.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() {
      _sending = true;
      _result = null;
    });
    try {
      final bal = await CreatorStudioService.adminGrant(
        adminKey: _key.text.trim(),
        user: _user.text.trim(),
        credits: credits,
        kind: _kind,
        note: _note.text.trim(),
        amountUsd: double.tryParse(_amount.text.trim()) ?? 0,
        reference: _reference.text.trim(),
        expiresDays: _kind == 'grant' ? 90 : null,
      );
      setState(() {
        _ok = true;
        _result = 'Added. ${_user.text.trim()} now has ${creditsLabel(bal.available)}.';
      });
      _reference.clear();
    } on StudioException catch (e) {
      setState(() {
        _ok = false;
        _result = e.message;
      });
    } catch (_) {
      setState(() {
        _ok = false;
        _result = "Couldn't reach Viyo. Try again.";
      });
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(backgroundColor: AppColors.background, title: const Text('Give Studio credits')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(padding: const EdgeInsets.all(20), children: [
            TextField(controller: _key, obscureText: true, decoration: studioField('Admin key')),
            const SizedBox(height: 12),
            TextField(controller: _user, decoration: studioField('User', hint: '@username or user ID')),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'purchase', label: Text('Paid (MoMo / PayPal)')),
                ButtonSegment(value: 'grant', label: Text('Free gift')),
              ],
              selected: {_kind},
              onSelectionChanged: (v) => setState(() => _kind = v.first),
            ),
            const SizedBox(height: 12),
            TextField(controller: _credits, keyboardType: TextInputType.number, decoration: studioField('Credits')),
            const SizedBox(height: 6),
            Wrap(spacing: 6, children: [
              for (final n in [100, 500, 1500, 4000, 10000])
                ActionChip(label: Text('$n'), onPressed: () => setState(() => _credits.text = '$n')),
            ]),
            const SizedBox(height: 12),
            if (_kind == 'purchase') ...[
              TextField(controller: _amount, keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: studioField('Amount received (USD)', hint: 'e.g. 5.88')),
              const SizedBox(height: 12),
              TextField(controller: _reference, decoration: studioField('Payment reference', hint: 'MoMo / PayPal transaction ID')),
              const SizedBox(height: 12),
            ] else
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text('Free credits expire after 90 days and are used before paid ones.',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
              ),
            TextField(controller: _note, decoration: studioField('Note (optional)')),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _sending ? null : _send,
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14)),
              icon: const Icon(Icons.bolt),
              label: Text(_sending ? 'Adding…' : 'Add credits', style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            if (_result != null) ...[
              const SizedBox(height: 14),
              Text(_result!, style: TextStyle(color: _ok ? AppColors.success : AppColors.danger, fontSize: 13)),
            ],
          ]),
        ),
      ),
    );
  }
}
