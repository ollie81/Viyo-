import 'package:flutter/material.dart';
import '../../services/donation_service.dart';
import '../../services/pending_purchase.dart';
import '../../theme/app_theme.dart';
import '../../widgets/purchase_ui.dart';
import '../../widgets/viyo_toast.dart';

/// Support a creator with real money through NardoPay (never coins). The donor picks a US-dollar amount and an
/// optional message here; VIYO converts the amount to francs and NardoPay's page opens in this tab for exactly that; when NardoPay sends them back, this screen reopens
/// (HomeShell) and checks the server until NardoPay's payment is confirmed. The creator receives 80%, available to
/// withdraw after the 14-day hold.
class DonateScreen extends StatefulWidget {
  final String creatorId;
  final String creatorName;

  /// Set when coming back from NardoPay: keep checking this donation.
  final String? resumeDonationId;
  final DonationApi api;

  const DonateScreen({
    super.key,
    required this.creatorId,
    required this.creatorName,
    this.resumeDonationId,
    this.api = const DonationApi(),
  });

  @override
  State<DonateScreen> createState() => _DonateScreenState();
}

class _DonateScreenState extends State<DonateScreen> {
  final _message = TextEditingController();
  final _custom = TextEditingController();
  DonationOptions _options = const DonationOptions(available: true);
  int? _cents = 500; // $5 preselected
  bool _customMode = false;
  bool _starting = false;
  bool _waiting = false;
  String? _error;
  String? _toast;
  int _waitToken = 0;

  @override
  void initState() {
    super.initState();
    final resume = widget.resumeDonationId;
    if (resume != null) WidgetsBinding.instance.addPostFrameCallback((_) => _waitForPaid(resume));
    widget.api.options().then((o) {
      if (mounted && o.available) setState(() => _options = o);
    });
  }

  /// The chosen amount in cents, or null when the custom amount isn't valid.
  int? get _chosenCents {
    if (!_customMode) return _cents;
    final v = double.tryParse(_custom.text.trim().replaceAll('\$', '').replaceAll(',', '.'));
    if (v == null) return null;
    final c = (v * 100).round();
    return c >= _options.minCents && c <= _options.maxCents ? c : null;
  }

  static String _usd(int cents) => cents % 100 == 0
      ? '\$${cents ~/ 100}'
      : '\$${(cents / 100).toStringAsFixed(2)}';

  @override
  void dispose() {
    _message.dispose();
    _custom.dispose();
    super.dispose();
  }

  void _showToast(String m) {
    setState(() => _toast = m);
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _toast == m) setState(() => _toast = null);
    });
  }

  Future<void> _start() async {
    final cents = _chosenCents;
    if (_starting || _waiting || cents == null) return;
    setState(() {
      _starting = true;
      _error = null;
    });
    try {
      final d = await widget.api.start(widget.creatorId, _message.text.trim(), cents);
      final link = d.paymentLink;
      if (link == null) throw Exception('The NardoPay page couldn\'t be opened. Please try again.');
      await PendingPurchase.save('donation', d.id);
      if (!await openCheckoutPage(link)) {
        await PendingPurchase.clear();
        throw Exception('The NardoPay page couldn\'t be opened. Please try again.');
      }
      if (mounted) await _waitForPaid(d.id);
    } catch (e) {
      if (mounted) setState(() => _error = '$e'.replaceFirst(RegExp(r'^Exception:\s*'), ''));
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _waitForPaid(String id) async {
    final token = ++_waitToken;
    bool mine() => mounted && token == _waitToken;
    setState(() => _waiting = true);
    try {
      for (var i = 0; i < 225 && mine(); i++) {
        try {
          final d = await widget.api.status(id);
          if (!mine()) return;
          if (d.status == 'paid') {
            await PendingPurchase.clear();
            if (!mounted || token != _waitToken) return;
            _showToast('Thank you! Your donation reached ${widget.creatorName}.');
            await Future.delayed(const Duration(milliseconds: 1200));
            if (mounted) Navigator.of(context).pop(true);
            return;
          }
          if (d.status == 'failed' || d.status == 'expired') {
            await PendingPurchase.clear();
            if (mine()) setState(() => _error = 'The payment didn\'t go through. Nothing was charged for it.');
            return;
          }
        } catch (_) {
          // A network blip: try again on the next check.
        }
        await Future.delayed(const Duration(seconds: 4));
      }
      if (mine()) {
        await PendingPurchase.clear();
        _showToast('Still waiting for NardoPay. If you paid, the creator will receive it soon.');
      }
    } finally {
      if (mounted && token == _waitToken) setState(() => _waiting = false);
    }
  }

  Future<void> _cancel() async {
    _waitToken++;
    await PendingPurchase.clear();
    if (mounted) setState(() => _waiting = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(backgroundColor: AppColors.background, title: const Text('Support a creator')),
      body: Stack(
        children: [
          PurchaseBody(
            bottom: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                PurchaseButton(
                  label: _chosenCents == null
                      ? 'Choose an amount'
                      : 'Donate ${_usd(_chosenCents!)}${(_options.feePercent ?? 0) > 0 ? ' + fee' : ''}',
                  accent: AppColors.coin,
                  busy: _starting,
                  onPressed: _waiting || _chosenCents == null ? null : _start,
                ),
                PurchaseFinePrint([
                  'Pay by card or mobile money on NardoPay\'s secure page.',
                  if ((_options.feePercent ?? 0) > 0)
                    'NardoPay adds a payment fee of about ${_options.feePercent!.round()}%.',
                  'Donations are real money, not coins, and aren\'t refundable through VIYO.',
                ].join(' ')),
              ],
            ),
            children: [
              const SizedBox(height: 8),
              Center(
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.coin.withAlpha(28),
                    border: Border.all(color: AppColors.coin.withAlpha(120)),
                  ),
                  child: const Icon(Icons.volunteer_activism_rounded, size: 30, color: AppColors.coin),
                ),
              ),
              const SizedBox(height: 16),
              Text('Support ${widget.creatorName}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, height: 1.2)),
              const SizedBox(height: 8),
              const Text(
                'Send a one-time donation to say thanks for their work. 80% goes to the creator.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.45),
              ),
              const PurchaseSectionLabel('Amount'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in _options.presetsCents)
                    ChoiceChip(
                      label: Text(_usd(c)),
                      selected: !_customMode && _cents == c,
                      onSelected: _waiting ? null : (_) => setState(() {
                            _customMode = false;
                            _cents = c;
                          }),
                    ),
                  ChoiceChip(
                    label: const Text('Other'),
                    selected: _customMode,
                    onSelected: _waiting ? null : (_) => setState(() => _customMode = true),
                  ),
                ],
              ),
              if (_customMode) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _custom,
                  enabled: !_waiting,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    prefixText: '\$ ',
                    hintText: 'Amount in US dollars',
                    helperText: '${_usd(_options.minCents)} to ${_usd(_options.maxCents)}',
                  ),
                ),
              ],
              if (_chosenCents != null && (_options.feePercent ?? 0) > 0) ...[
                const SizedBox(height: 6),
                Text(
                  '${_usd(_chosenCents!)} + about \$${(_chosenCents! * _options.feePercent! / 10000).toStringAsFixed(2)} NardoPay fee',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
              ],
              const PurchaseSectionLabel('Message (optional)'),
              TextField(
                controller: _message,
                maxLength: 200,
                maxLines: 3,
                enabled: !_waiting,
                decoration: const InputDecoration(hintText: 'Say something nice…'),
              ),
              if (_waiting) ...[
                const SizedBox(height: 8),
                PurchaseNotice(
                  tone: NoticeTone.waiting,
                  title: 'Waiting for payment confirmation',
                  message: 'Your donation is confirmed here as soon as NardoPay confirms the payment.',
                  action: OutlinedButton(onPressed: _cancel, child: const Text('I didn\'t pay · Cancel')),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 8),
                PurchaseNotice(tone: NoticeTone.error, title: 'Donation not completed', message: _error),
              ],
            ],
          ),
          if (_toast != null) ViyoToast(message: _toast!),
        ],
      ),
    );
  }
}
