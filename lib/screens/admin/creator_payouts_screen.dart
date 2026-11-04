import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/wallet_service.dart';
import '../../theme/app_theme.dart';

/// Admin: creators waiting to be paid. Send the money in PayPal or mobile
/// money, then tap "Mark as paid". Same admin key as the other admin tools.
class CreatorPayoutsScreen extends StatefulWidget {
  const CreatorPayoutsScreen({super.key});

  @override
  State<CreatorPayoutsScreen> createState() => _CreatorPayoutsScreenState();
}

class _CreatorPayoutsScreenState extends State<CreatorPayoutsScreen> {
  final _keyController = TextEditingController();
  String? _adminKey;
  String _status = 'pending';
  List<AdminWithdrawal> _items = [];
  bool _loading = false;
  String? _error;
  final Set<String> _acting = {};

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    final key = _keyController.text.trim();
    if (key.isEmpty) return;
    setState(() => _adminKey = key);
    await _load();
  }

  Future<void> _load() async {
    final key = _adminKey;
    if (key == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await WalletService.adminListWithdrawals(key, status: _status);
      if (mounted) setState(() => _items = items);
    } catch (e) {
      final message = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
      if (mounted) {
        setState(() {
          _error = message;
          if (message.contains('Invalid admin key')) _adminKey = null;
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _settle(AdminWithdrawal w, {required bool paid}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(paid ? 'Mark as paid?' : 'Reject this withdrawal?'),
        content: Text(paid
            ? 'Only do this after you have sent \$${w.usdAmount.toStringAsFixed(2)} to\n${w.payoutDestination ?? ''}'
            : 'The creator gets their earnings back and can request again, e.g. after fixing their payout details.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(paid ? 'Mark as paid' : 'Reject')),
        ],
      ),
    );
    if (ok != true || _adminKey == null) return;
    setState(() => _acting.add(w.id));
    try {
      await WalletService.adminSettle(_adminKey!, w.id, paid: paid);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _acting.remove(w.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: AppColors.background, title: const Text('Creator payouts')),
      body: _adminKey == null ? _keyPrompt() : _list(),
    );
  }

  Widget _keyPrompt() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.admin_panel_settings_outlined, size: 40, color: AppColors.textMuted),
            const SizedBox(height: 16),
            TextField(
              controller: _keyController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Admin key'),
              onSubmitted: (_) => _unlock(),
            ),
            const SizedBox(height: 14),
            SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _unlock, child: const Text('Unlock'))),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _list() {
    final total = _items.fold<double>(0, (sum, w) => sum + w.usdAmount);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'pending', label: Text('To pay')),
              ButtonSegment(value: 'paid', label: Text('Paid')),
              ButtonSegment(value: 'rejected', label: Text('Rejected')),
            ],
            selected: {_status},
            onSelectionChanged: (v) {
              setState(() => _status = v.first);
              _load();
            },
          ),
          const SizedBox(height: 14),
          if (_loading)
            const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            Text(_error!, style: const TextStyle(color: AppColors.danger))
          else if (_items.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Text(_status == 'pending' ? 'Nobody is waiting to be paid.' : 'Nothing here yet.',
                    style: const TextStyle(color: AppColors.textMuted)),
              ),
            )
          else ...[
            if (_status == 'pending')
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text('${_items.length} to pay · \$${total.toStringAsFixed(2)} in total',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            for (final w in _items) _tile(w),
          ],
        ],
      ),
    );
  }

  Widget _tile(AdminWithdrawal w) {
    final who = (w.displayName?.isNotEmpty ?? false) ? w.displayName! : '@${w.username ?? 'creator'}';
    final busy = _acting.contains(w.id);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(who, style: const TextStyle(fontWeight: FontWeight.w700))),
              Text('\$${w.usdAmount.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: AppColors.success)),
            ],
          ),
          const SizedBox(height: 4),
          Text('${w.coins} coins · requested ${(w.createdAt ?? '').split('T').first}',
              style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
          const SizedBox(height: 8),
          InkWell(
            onTap: () {
              Clipboard.setData(ClipboardData(text: w.payoutDestination ?? ''));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Payout details copied')));
            },
            child: Row(
              children: [
                Expanded(child: Text(w.payoutDestination ?? 'No payout details', style: const TextStyle(fontSize: 13))),
                const Icon(Icons.copy, size: 15, color: AppColors.textMuted),
              ],
            ),
          ),
          if (w.status == 'pending') ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: busy ? null : () => _settle(w, paid: false),
                    child: const Text('Reject'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: busy ? null : () => _settle(w, paid: true),
                    child: Text(busy ? 'Saving...' : 'Mark as paid'),
                  ),
                ),
              ],
            ),
          ] else if (w.paidAt != null) ...[
            const SizedBox(height: 6),
            Text('Paid ${w.paidAt!.split('T').first}', style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
          ],
        ],
      ),
    );
  }
}
