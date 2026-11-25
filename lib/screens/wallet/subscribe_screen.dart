import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/checkout_options_service.dart';
import '../../services/subscription_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/purchase_ui.dart';
import '../../widgets/viyo_toast.dart';

/// Viyo Premium: a real-money recurring subscription (never paid with coins) for unlimited episode access, through
/// Lemon Squeezy's hosted checkout, with the same "open externally, check again on app resume" pattern as the coin
/// hosted checkouts.
///
/// Plans and prices come from the server (GET /api/v1/checkout/options), which reads each plan's real price from
/// Lemon Squeezy and marks a plan purchasable only when its checkout is configured. A plan without a real price is
/// shown as unavailable; no price is ever written into the app.
///
/// Android-gated like BuyCoinsScreen: Google Play policy requires Play Billing for recurring digital goods inside a
/// Play-distributed app, so the Android app doesn't offer Premium.
class SubscribeScreen extends StatefulWidget {
  /// For tests: where the options and the subscription status come from, and the platform.
  final Future<CheckoutOptions> Function()? loadOptions;
  final Future<SubscriptionStatus> Function()? loadStatus;
  final PurchasePlatform? platform;

  const SubscribeScreen({super.key, this.loadOptions, this.loadStatus, this.platform});

  @override
  State<SubscribeScreen> createState() => _SubscribeScreenState();
}

/// What Premium really does today (see the backend's episodes.py: an active subscriber skips the per-episode coin
/// paywall). Nothing else is promised.
const _benefits = <(IconData, String, String)>[
  (Icons.all_inclusive_rounded, 'Every episode, unlocked', 'Watch every episode of every series without spending coins.'),
  (Icons.play_circle_outline_rounded, 'Binge at your own pace', 'No per-episode unlocks while your plan is active.'),
  (Icons.monetization_on_outlined, 'Keep your coins', 'Your coin balance stays yours for AI features and boosts.'),
];

class _SubscribeScreenState extends State<SubscribeScreen> with WidgetsBindingObserver {
  PurchasePlatform get _platform => widget.platform ?? currentPurchasePlatform;
  bool get _isAndroid => _platform == PurchasePlatform.android;

  SubscriptionStatus? _status;
  List<PremiumPlan> _plans = [];
  String? _selectedPlan;
  bool _loading = true;
  String? _error;
  bool _purchasing = false;
  bool _awaitingCheckoutResult = false;
  bool _checking = false;
  String? _purchaseError;
  String? _toast;

  PremiumPlan? get _selected {
    for (final p in _plans) {
      if (p.plan == _selectedPlan && p.available) return p;
    }
    return null;
  }

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
    _pollForActive();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final status = await (widget.loadStatus ?? SubscriptionService.getStatus)();
      CheckoutOptions? options;
      if (!_isAndroid && !status.isSubscribed) {
        options = await (widget.loadOptions ?? CheckoutOptionsService.fetch)();
      }
      if (!mounted) return;
      final plans = options?.premiumPlans ?? const <PremiumPlan>[];
      final available = plans.where((p) => p.available).map((p) => p.plan).toList();
      setState(() {
        _status = status;
        _plans = plans;
        _selectedPlan = available.contains(_selectedPlan)
            ? _selectedPlan
            : (available.contains('monthly') ? 'monthly' : (available.isNotEmpty ? available.first : null));
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _subscribe() async {
    final plan = _selected;
    if (plan == null || _purchasing) return;
    setState(() {
      _purchasing = true;
      _purchaseError = null;
    });
    try {
      final checkoutUrl = await SubscriptionService.createCheckout(plan.plan);
      final opened = await launchUrl(Uri.parse(checkoutUrl), mode: LaunchMode.externalApplication);
      if (!opened) {
        setState(() => _purchaseError = 'The checkout page couldn\'t be opened. Please try again.');
        return;
      }
      _awaitingCheckoutResult = true;
      _showToast('Finish subscribing on the checkout page, then come back here.');
    } catch (e) {
      setState(() => _purchaseError = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), ''));
    } finally {
      if (mounted) setState(() => _purchasing = false);
    }
  }

  Future<void> _pollForActive() async {
    setState(() => _checking = true);
    try {
      for (var i = 0; i < 6; i++) {
        await Future.delayed(const Duration(seconds: 2));
        try {
          final status = await SubscriptionService.getStatus();
          if (status.isSubscribed) {
            if (mounted) {
              setState(() => _status = status);
              _showToast('Welcome to VIYO Premium');
              Navigator.of(context).pop(true);
            }
            return;
          }
        } catch (_) {
          // Keep checking: a passing network error shouldn't end the attempt early.
        }
      }
      if (mounted) {
        _showToast("Payment received. Premium will switch on shortly if it hasn't already.");
        await _load();
      }
    } finally {
      if (mounted) setState(() => _checking = false);
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
      backgroundColor: AppColors.background,
      appBar: AppBar(backgroundColor: AppColors.background, title: const Text('VIYO Premium')),
      body: Stack(
        children: [
          _body(),
          if (_toast != null) ViyoToast(message: _toast!),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) return const PurchaseSkeleton(cards: 3);
    if (_error != null) {
      return PurchaseBody(children: [
        const SizedBox(height: 24),
        PurchaseNotice(
          tone: NoticeTone.error,
          title: 'Premium couldn\'t be loaded',
          message: _error,
          action: OutlinedButton(onPressed: _load, child: const Text('Try again')),
        ),
      ]);
    }
    final status = _status;
    if (status != null && status.isSubscribed) return _activeMember(status);

    final onSale = _plans.any((p) => p.available);
    final selected = _selected;
    final monthly = _plans.where((p) => p.plan == 'monthly' && p.available && p.interval == 'month').firstOrNull;

    return PurchaseBody(
      bottom: _isAndroid
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                PurchaseButton(
                  label: selected != null
                      ? 'Subscribe · ${selected.priceLabel} / ${selected.periodLabel}'
                      : (onSale ? 'Choose a plan' : 'Not available yet'),
                  accent: AppColors.primary,
                  busy: _purchasing,
                  onPressed: selected != null && !_checking ? _subscribe : null,
                ),
                PurchaseFinePrint(onSale
                    ? 'Paid with money, not coins. Renews automatically until you cancel; manage or cancel it from '
                        'your Lemon Squeezy receipt email.'
                    : 'Premium is paid with money, not coins.'),
              ],
            ),
      children: [
        const SizedBox(height: 8),
        const _Hero(),
        const SizedBox(height: 20),
        for (final (icon, title, text) in _benefits) _Benefit(icon: icon, title: title, text: text),
        if (_isAndroid) ...[
          const SizedBox(height: 16),
          const PurchaseNotice(
            tone: NoticeTone.info,
            title: 'Premium isn\'t available in this app',
            message: 'You can keep unlocking episodes with coins.',
          ),
        ] else ...[
          const PurchaseSectionLabel('Choose your plan'),
          if (!onSale) ...[
            const PurchaseNotice(
              tone: NoticeTone.info,
              title: 'Premium subscriptions aren\'t open yet',
              message: 'Plans and prices will appear here as soon as they are. Until then, you can keep unlocking '
                  'episodes with coins.',
            ),
            const SizedBox(height: PurchaseUi.gap),
          ],
          for (final plan in _plans)
            Padding(
              padding: const EdgeInsets.only(bottom: PurchaseUi.gap),
              child: _PlanCard(
                plan: plan,
                selected: plan.plan == _selectedPlan,
                savePercent: _yearlySaving(plan, monthly),
                enabled: !_purchasing && !_checking,
                onTap: () => setState(() => _selectedPlan = plan.plan),
              ),
            ),
          if (_checking)
            const PurchaseNotice(
              tone: NoticeTone.waiting,
              title: 'Checking your subscription',
              message: 'This takes a few seconds after you finish paying.',
            ),
          if (_purchaseError != null)
            PurchaseNotice(tone: NoticeTone.error, title: 'Subscription not started', message: _purchaseError),
        ],
      ],
    );
  }

  /// "Save N%" for a yearly plan against twelve months of the monthly plan, both real prices in the same currency.
  static int? _yearlySaving(PremiumPlan plan, PremiumPlan? monthly) {
    if (plan.plan != 'yearly' || !plan.available || monthly == null) return null;
    if (plan.interval != 'year' || (plan.intervalCount ?? 1) != 1 || (monthly.intervalCount ?? 1) != 1) return null;
    if (plan.currency != monthly.currency || plan.priceCents == null || monthly.priceCents == null) return null;
    final saving = (1 - plan.priceCents! / (monthly.priceCents! * 12)) * 100;
    return saving >= 5 ? saving.floor() : null;
  }

  Widget _activeMember(SubscriptionStatus status) {
    final renewsAt = status.renewsAt;
    final endsAt = status.endsAt;
    return PurchaseBody(children: [
      const SizedBox(height: 8),
      const _Hero(member: true),
      const SizedBox(height: 20),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(PurchaseUi.radius),
          border: Border.all(color: AppColors.primary.withAlpha(110)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text(
                switch (status.plan) { 'weekly' => 'Weekly plan', 'yearly' => 'Yearly plan', _ => 'Monthly plan' },
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
              const Spacer(),
              const PurchaseChip('Active', color: AppColors.success),
            ]),
            if (renewsAt != null) ...[
              const SizedBox(height: 6),
              Text('Renews ${renewsAt.split('T').first}',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            ] else if (endsAt != null) ...[
              const SizedBox(height: 6),
              Text('Ends ${endsAt.split('T').first}',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            ],
            const SizedBox(height: 12),
            const Text(
              'Manage or cancel your subscription from the receipt email Lemon Squeezy sent you.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.4),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      for (final (icon, title, text) in _benefits) _Benefit(icon: icon, title: title, text: text),
    ]);
  }
}

class _Hero extends StatelessWidget {
  final bool member;
  const _Hero({this.member = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.primary.withAlpha(24),
            border: Border.all(color: AppColors.primary.withAlpha(120)),
          ),
          child: const Icon(Icons.workspace_premium_rounded, size: 32, color: AppColors.primary),
        ),
        const SizedBox(height: 16),
        Text(
          member ? 'You\'re a Premium member' : 'Unlimited episodes,\nno coins needed',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, height: 1.2),
        ),
        const SizedBox(height: 8),
        Text(
          member
              ? 'Every episode of every series is unlocked for you.'
              : 'One subscription unlocks every drama on VIYO, instead of paying coins episode by episode.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.45),
        ),
      ],
    );
  }
}

class _Benefit extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;
  const _Benefit({required this.icon, required this.title, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                const SizedBox(height: 2),
                Text(text, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final PremiumPlan plan;
  final bool selected;
  final int? savePercent;
  final bool enabled;
  final VoidCallback onTap;

  const _PlanCard({
    required this.plan,
    required this.selected,
    required this.savePercent,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final price = plan.priceLabel;
    return SelectableCard(
      selected: selected && plan.available,
      enabled: enabled && plan.available,
      accent: AppColors.primary,
      onTap: onTap,
      semanticsLabel: price != null ? '${plan.title}, $price per ${plan.periodLabel}' : '${plan.title}, not available',
      child: Row(
        children: [
          SelectionDot(selected: selected && plan.available, accent: AppColors.primary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(plan.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    if (savePercent != null) PurchaseChip('Save $savePercent%', color: AppColors.coin),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  plan.available ? 'Billed every ${plan.periodLabel}' : (plan.reason ?? 'Not available right now'),
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (price != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(price, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                Text('/ ${plan.periodLabel}', style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
              ],
            )
          else
            const PurchaseChip('Not available', color: AppColors.textMuted),
        ],
      ),
    );
  }
}
