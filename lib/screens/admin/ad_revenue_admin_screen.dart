import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/ad_revenue_service.dart';
import '../../theme/app_theme.dart';

typedef AdminMonthCall = Future<Map> Function(String key, String month);
typedef AdminCloseCall = Future<Map> Function(String key, String month, double feedUsd, double unlockUsd, String note);

/// Admin: once a month, enter what the AdMob report says VIYO's ads earned last month; half goes to creators, shared
/// by the ads shown on their content. A month is closed once. The admin key stays in memory only.
class AdRevenueAdminScreen extends StatefulWidget {
  const AdRevenueAdminScreen(
      {super.key, this.month = AdRevenueService.adminMonth, this.close = AdRevenueService.adminClose, this.now});
  final AdminMonthCall month;
  final AdminCloseCall close;
  final DateTime? now;

  @override
  State<AdRevenueAdminScreen> createState() => _AdRevenueAdminScreenState();
}

class _AdRevenueAdminScreenState extends State<AdRevenueAdminScreen> {
  final _key = TextEditingController();
  final _feed = TextEditingController();
  final _unlock = TextEditingController();
  final _note = TextEditingController();
  late String _monthStr;
  Map? _info;
  Map? _done;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final n = (widget.now ?? DateTime.now()).toUtc();
    final last = DateTime.utc(n.year, n.month - 1, 1);
    _monthStr = '${last.year}-${last.month.toString().padLeft(2, '0')}';
    for (final c in [_feed, _unlock]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final c in [_key, _feed, _unlock, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _run(Future<void> Function() f) async {
    if (_key.text.trim().isEmpty) {
      setState(() => _error = 'Enter the admin key.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await f();
    } catch (e) {
      if (mounted) setState(() => _error = '$e'.replaceFirst(RegExp(r'^Exception:\s*'), ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _check() => _run(() async {
        final i = await widget.month(_key.text.trim(), _monthStr);
        if (mounted) setState(() => _info = i);
      });

  double? _amount(TextEditingController c) {
    final v = double.tryParse(c.text.trim().replaceAll(',', ''));
    return v == null || v < 0 ? null : v;
  }

  Future<void> _close() async {
    final feed = _amount(_feed), unlock = _amount(_unlock);
    if (feed == null || unlock == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Close $_monthStr?'),
        content: Text('In-feed ads earned \$${feed.toStringAsFixed(2)} and unlock ads \$${unlock.toStringAsFixed(2)}. '
            'Creators get half: \$${((feed + unlock) / 2).toStringAsFixed(2)}. This can be done only once.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Close the month')),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() async {
      final d = await widget.close(_key.text.trim(), _monthStr, feed, unlock, _note.text.trim());
      if (mounted) setState(() => _done = d);
    });
  }

  InputDecoration _dec(String label, {String? prefix, String? helper}) => InputDecoration(
        labelText: label,
        prefixText: prefix,
        helperText: helper,
        helperMaxLines: 2,
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
      );

  @override
  Widget build(BuildContext context) {
    final info = _info;
    final canClose = info?['can_close'] == true && _amount(_feed) != null && _amount(_unlock) != null && !_busy;
    final money = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))];
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(backgroundColor: AppColors.background, title: const Text('Ad revenue')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text(
          'Once a month: enter what the AdMob report says each ad unit earned last month. Half goes to creators, shared '
          'by the ads shown on their content. Ads watched for coins aren\'t shared.',
          style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.4),
        ),
        const SizedBox(height: 14),
        TextField(controller: _key, obscureText: true, decoration: _dec('Admin key')),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: Text('Month: $_monthStr', style: const TextStyle(fontWeight: FontWeight.w700))),
          OutlinedButton(onPressed: _busy ? null : _check, child: const Text('Check')),
        ]),
        if (info != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: AppTheme.card(),
            child: Text(
              info['closed'] == true
                  ? 'Already closed: \$${(info['summary']?['paid_usd'] as num? ?? 0).toStringAsFixed(2)} paid to '
                      '${info['summary']?['creators'] ?? 0} creators.'
                  : '${info['feed_ads']} in-feed ads and ${info['unlock_ads']} unlock ads on ${info['creators']} '
                      'creators\' content.',
              style: const TextStyle(fontSize: 13),
            ),
          ),
          if (info['can_close'] == true) ...[
            const SizedBox(height: 14),
            TextField(
                controller: _feed,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: money,
                decoration: _dec('In-feed ads earned', prefix: '\$ ', helper: 'AdMob → Reports → the interstitial ad unit, that month')),
            const SizedBox(height: 10),
            TextField(
                controller: _unlock,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: money,
                decoration: _dec('Episode-unlock ads earned', prefix: '\$ ', helper: 'AdMob → the episode-unlock rewarded ad unit, that month')),
            const SizedBox(height: 10),
            TextField(controller: _note, maxLength: 300, decoration: _dec('Note (optional)')),
            const SizedBox(height: 6),
            ElevatedButton(onPressed: canClose ? _close : null, child: const Text('Close the month and pay creators')),
          ],
        ],
        if (_done != null)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Text(
                'Closed. \$${(_done!['paid_usd'] as num? ?? 0).toStringAsFixed(2)} credited to ${_done!['creators']} creators.',
                style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w700)),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_error!, style: const TextStyle(color: AppColors.danger)),
          ),
      ]),
    );
  }
}
