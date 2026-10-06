import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/subscription_service.dart';
import '../../theme/app_theme.dart';

/// Viyo Premium: a flat weekly or monthly price for unlimited episode
/// access (no coins spent per episode) via Lemon Squeezy's hosted
/// checkout — same "open externally, poll on app resume" pattern as
/// BuyCoinsScreen's Paystack/Flutterwave/Lemon Squeezy coin purchases,
/// since there's no direct callback from an external browser tab.
///
/// Android-gated out exactly like BuyCoinsScreen's hosted-checkout
/// options: Google Play policy requires any recurring digital good
/// consumed inside an app distributed through Google Play to sell
/// through Play Billing, not a third-party processor like Lemon
/// Squeezy — so this screen only offers to subscribe on web (and
/// non-Android native platforms), matching coins' own anti-steering
/// workaround rather than risking the Play Store listing.
class SubscribeScreen extends StatefulWidget {
  const SubscribeScreen({super.key});

  @override
  State<SubscribeScreen> createState() => _SubscribeScreenState();
}

class _SubscribeScreenState extends State<SubscribeScreen> with WidgetsBindingObserver {
  static bool get _isAndroidNative => !kIsWeb && Platform.isAndroid;

  SubscriptionStatus? _status;
  bool _loading = true;
  String? _error;
  String? _purchasingPlan;
  bool _awaitingCheckoutResult = false;
  String? _toast;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !_awaitingCheckoutResult) return;
    _awaitingCheckoutResult = false;
    _showToast('Checking your subscription…');
    _pollForActive();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final status = await SubscriptionService.getStatus();
      if (!mounted) return;
      setState(() => _status = status);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _subscribe(String plan) async {
    setState(() => _purchasingPlan = plan);
    try {
      final checkoutUrl = await SubscriptionService.createCheckout(plan);
      final opened = await launchUrl(Uri.parse(checkoutUrl), mode: LaunchMode.externalApplication);
      if (!opened) {
        _showToast('Could not open the checkout page.');
        return;
      }
      _awaitingCheckoutResult = true;
      _showToast('Complete your subscription in the browser, then come back here.');
    } catch (e) {
      _showToast(e.toString().replaceFirst(RegExp(r'^Exception:\s*'), ''));
    } finally {
      if (mounted) setState(() => _purchasingPlan = null);
    }
  }

  Future<void> _pollForActive() async {
    for (var i = 0; i < 6; i++) {
      await Future.delayed(const Duration(seconds: 2));
      try {
        final status = await SubscriptionService.getStatus();
        if (status.isSubscribed) {
          if (mounted) {
            setState(() => _status = status);
            _showToast('Welcome to Viyo Premium! 🎉');
            Navigator.of(context).pop(true);
          }
          return;
        }
      } catch (_) {
        // Keep polling — a transient network error here shouldn't end
        // the attempt early.
      }
    }
    if (mounted) {
      _showToast("Payment received — Premium will activate shortly if it hasn't already.");
      await _load();
    }
  }

  void _showToast(String message) {
    setState(() => _toast = message);
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _toast == message) setState(() => _toast = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: const Text('Viyo Premium'),
      ),
      body: Stack(
        children: [
          _body(),
          if (_toast != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 24,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.surfaceBorder),
                  ),
                  child: Text(_toast!, style: const TextStyle(fontSize: 13)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, style: const TextStyle(color: AppColors.danger), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    final status = _status;
    if (status != null && status.isSubscribed) {
      return _activeSubscriptionCard(status);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        const Icon(Icons.workspace_premium_outlined, size: 48, color: AppColors.coin),
        const SizedBox(height: 14),
        const Text(
          'Unlimited episodes, no coins needed',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        const Text(
          'Every drama, every episode — watch as much as you want while subscribed, '
          'instead of spending coins one episode at a time.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        if (_isAndroidNative)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: AppTheme.card(),
            child: const Text(
              "Subscriptions aren't available in the Android app yet — open viyo.app in your "
              'phone or computer\'s browser to subscribe.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          )
        else ...[
          _planCard(
            plan: 'weekly',
            title: 'Weekly',
            subtitle: 'Try it out, or finish a binge',
          ),
          const SizedBox(height: 12),
          _planCard(
            plan: 'monthly',
            title: 'Monthly',
            subtitle: 'Best value for regular watching',
            highlighted: true,
          ),
          const SizedBox(height: 12),
          _planCard(
            plan: 'yearly',
            title: 'Yearly',
            subtitle: 'Biggest savings — less than 6 months\' worth',
          ),
        ],
      ],
    );
  }

  Widget _planCard({
    required String plan,
    required String title,
    required String subtitle,
    bool highlighted = false,
  }) {
    final busy = _purchasingPlan == plan;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: highlighted ? AppColors.primary : AppColors.surfaceBorder, width: highlighted ? 1.5 : 1),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                const SizedBox(height: 3),
                Text(subtitle, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: _purchasingPlan != null ? null : () => _subscribe(plan),
            style: highlighted ? null : ElevatedButton.styleFrom(backgroundColor: AppColors.surfaceBorder),
            child: busy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Subscribe'),
          ),
        ],
      ),
    );
  }

  Widget _activeSubscriptionCard(SubscriptionStatus status) {
    final renewsAt = status.renewsAt;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.workspace_premium, size: 48, color: AppColors.coin),
            const SizedBox(height: 14),
            const Text("You're a Viyo Premium member", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 8),
            Text(
              switch (status.plan) {
                'weekly' => 'Weekly plan',
                'yearly' => 'Yearly plan',
                _ => 'Monthly plan',
              },
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            if (renewsAt != null) ...[
              const SizedBox(height: 4),
              Text(
                'Renews ${renewsAt.split('T').first}',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
            ],
            const SizedBox(height: 16),
            const Text(
              'Manage or cancel your subscription from the confirmation email Lemon Squeezy sent you.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 11.5),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
