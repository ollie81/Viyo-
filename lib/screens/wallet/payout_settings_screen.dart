import 'package:flutter/material.dart';

import '../../services/wallet_service.dart';
import '../../theme/app_theme.dart';

/// Where a creator wants their earnings sent: PayPal or mobile money.
/// Payouts are sent by the Viyo team, so these details must be right.
class PayoutSettingsScreen extends StatefulWidget {
  final PayoutSettings? current;
  const PayoutSettingsScreen({super.key, this.current});

  @override
  State<PayoutSettingsScreen> createState() => _PayoutSettingsScreenState();
}

class _PayoutSettingsScreenState extends State<PayoutSettingsScreen> {
  static const _networks = ['MTN', 'Airtel', 'M-Pesa', 'Orange', 'Other'];

  late String _method = widget.current?.method ?? 'paypal';
  late final _email = TextEditingController(text: widget.current?.paypalEmail ?? '');
  late final _phone = TextEditingController(text: widget.current?.momoPhone ?? '');
  late final _name = TextEditingController(text: widget.current?.accountName ?? '');
  late final _country = TextEditingController(text: widget.current?.country ?? '');
  late String _network = _networks.contains(widget.current?.momoNetwork) ? widget.current!.momoNetwork! : 'MTN';
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_email, _phone, _name, _country]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await WalletService.savePayoutSettings(PayoutSettings(
        method: _method,
        paypalEmail: _method == 'paypal' ? _email.text.trim() : null,
        momoPhone: _method == 'mobile_money' ? _phone.text.trim() : null,
        momoNetwork: _method == 'mobile_money' ? _network : null,
        accountName: _name.text.trim().isEmpty ? null : _name.text.trim(),
        country: _country.text.trim().isEmpty ? null : _country.text.trim(),
      ));
      if (mounted) Navigator.of(context).pop(saved);
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final paypal = _method == 'paypal';
    return Scaffold(
      appBar: AppBar(backgroundColor: AppColors.background, title: const Text('Payout details')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const Text(
            'Where should we send your earnings? Payouts are sent by the Viyo team after you request a withdrawal.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 16),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'paypal', label: Text('PayPal'), icon: Icon(Icons.account_balance_wallet_outlined)),
              ButtonSegment(value: 'mobile_money', label: Text('Mobile money'), icon: Icon(Icons.phone_android)),
            ],
            selected: {_method},
            onSelectionChanged: _saving ? null : (v) => setState(() => _method = v.first),
          ),
          const SizedBox(height: 18),
          if (paypal) ...[
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'PayPal email', hintText: 'you@example.com'),
            ),
            const SizedBox(height: 6),
            const Text('The email address of the PayPal account that should receive the money.',
                style: TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
          ] else ...[
            DropdownButtonFormField<String>(
              value: _network,
              decoration: const InputDecoration(labelText: 'Network'),
              items: [for (final n in _networks) DropdownMenuItem(value: n, child: Text(n))],
              onChanged: _saving ? null : (v) => setState(() => _network = v ?? 'MTN'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Mobile money number', hintText: '+250 78 123 4567'),
            ),
            const SizedBox(height: 6),
            const Text('Include your country code.', style: TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
                labelText: paypal ? 'Full name (optional)' : 'Name on the account',
                hintText: 'As registered with ${paypal ? 'PayPal' : 'your network'}'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _country,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Country (optional)'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
          ],
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Saving...' : 'Save payout details'),
          ),
        ],
      ),
    );
  }
}
