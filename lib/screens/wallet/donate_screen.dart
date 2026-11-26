import 'package:flutter/material.dart';
import '../../services/donation_service.dart';
import '../../services/pending_purchase.dart';
import '../../theme/app_theme.dart';
import '../../widgets/purchase_ui.dart';
import '../../widgets/viyo_toast.dart';

/// Support a creator with real money through NardoPay (never coins). The donor writes an optional message here and
/// chooses the amount on NardoPay's page, which opens in this tab; when NardoPay sends them back, this screen reopens
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
  }

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  void _showToast(String m) {
    setState(() => _toast = m);
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _toast == m) setState(() => _toast = null);
    });
  }

  Future<void> _start() async {
    if (_starting || _waiting) return;
    setState(() {
      _starting = true;
      _error = null;
    });
    try {
      final d = await widget.api.start(widget.creatorId, _message.text.trim());
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
                  label: 'Continue to payment',
                  accent: AppColors.coin,
                  busy: _starting,
                  onPressed: _waiting ? null : _start,
                ),
                const PurchaseFinePrint('You choose the amount on NardoPay\'s secure page (card or mobile money). '
                    'Donations are real money, not coins, and aren\'t refundable through VIYO.'),
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
