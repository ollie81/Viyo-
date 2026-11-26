import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/checkout_options_service.dart';
import '../../services/nardopay_service.dart';
import '../../services/subscription_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/purchase_ui.dart';
import '../../widgets/viyo_toast.dart';

/// Viyo Premium: real money (never coins) for unlimited episode access. Two ways to pay, each shown only when the
/// server says it's genuinely available (GET /api/v1/checkout/options):
///
/// * NardoPay (web only): mobile money or card, ONE payment for a prepaid pass of 7, 30 or 365 days that does not
///   renew. The server prices it, creates the order and grants the pass only after NardoPay's signed confirmation;
///   this screen just opens the payment page and checks the order.
/// * Lemon Squeezy: a card subscription that renews automatically, at the prices read from Lemon Squeezy.
///
/// Android-gated like BuyCoinsScreen: Google Play policy requires Play Billing for recurring digital goods inside a
/// Play-distributed app, so the Android app doesn't offer Premium.
class SubscribeScreen extends StatefulWidget {
  /// For tests: where the options and the subscription status come from, the platform, and the NardoPay API.
  final Future<CheckoutOptions> Function()? loadOptions;
  final Future<SubscriptionStatus> Function()? loadStatus;
  final PurchasePlatform? platform;
  final NardopayApi nardopay;

  const SubscribeScreen(
      {super.key, this.loadOptions, this.loadStatus, this.platform, this.nardopay = const NardopayApi()});

  @override
  State<SubscribeScreen> createState() => _SubscribeScreenState();
}

/// What Premium really does today (the backend's episode paywall lets an active member through). Nothing else.
const _benefits = <(IconData, String, String)>[
  (Icons.all_inclusive_rounded, 'Every episode, unlocked', 'Watch every episode of every series without spending coins.'),
  (Icons.play_circle_outline_rounded, 'Binge at your own pace', 'No per-episode unlocks while Premium is active.'),
  (Icons.monetization_on_outlined, 'Keep your coins', 'Your coin balance stays yours for AI features and boosts.'),
];

const _planOrder = ['weekly', 'monthly', 'yearly'];
String _planTitle(String plan) => switch (plan) { 'weekly' => 'Weekly', 'yearly' => 'Yearly', _ => 'Monthly' };

/// One plan as shown for the chosen payment method.
class _Offer {
  final String plan;
  final bool available;
  final String? price;
  final String unit; // "month" for a subscription, "30 days" for a pass
  final String detail;
  final int? priceCents;
  final String? currency;
  const _Offer(this.plan, this.available, this.price, this.unit, this.detail, {this.priceCents, this.currency});
}

class _SubscribeScreenState extends State<SubscribeScreen> with WidgetsBindingObserver {
  PurchasePlatform get _platform => widget.platform ?? currentPurchasePlatform;
  bool get _isAndroid => _platform == PurchasePlatform.android;

  SubscriptionStatus? _status;
  CheckoutOptions? _options;
  List<String> _methods = [];
  String? _method;
  String? _selectedPlan;
  bool _loading = true;
  String? _error;
  bool _purchasing = false;
  bool _awaitingCheckoutResult = false;
  bool _checking = false;
  bool _waitingForNardopay = false;
  bool _extending = false; // a NardoPay member adding time
  String? _purchaseError;
  String? _toast;

  List<_Offer> get _offers {
    final o = _options;
    if (o == null || _method == null) return const [];
    if (_method == 'nardopay') {
      return [
        for (final plan in _planOrder)
          for (final p in o.nardopayPasses.where((p) => p.plan == plan))
            _Offer(p.plan, true, p.priceLabel, p.daysLabel, 'One payment for ${p.daysLabel} · doesn\'t renew',
                priceCents: p.priceCents, currency: p.currency),
      ];
    }
    return [
      for (final p in o.premiumPlans)
        _Offer(p.plan, p.available, p.priceLabel, p.periodLabel,
            p.available ? 'Renews every ${p.periodLabel}' : (p.reason ?? 'Not available right now'),
            priceCents: p.priceCents, currency: p.currency),
    ];
  }

  _Offer? get _selected {
    for (final o in _offers) {
      if (o.plan == _selectedPlan && o.available) return o;
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
      final options = _isAndroid ? null : await (widget.loadOptions ?? CheckoutOptionsService.fetch)();
      if (!mounted) return;
      setState(() {
        _status = status;
        _options = options;
        _methods = options?.premiumMethodsFor(_platform) ?? const [];
        _pickMethod(_methods.contains(_method) ? _method : (_methods.isNotEmpty ? _methods.first : null));
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Switches the payment method and keeps the chosen plan if that method offers it (else monthly, else the first).
  void _pickMethod(String? method) {
    _method = method;
    final available = _offers.where((o) => o.available).map((o) => o.plan).toList();
    _selectedPlan = available.contains(_selectedPlan)
        ? _selectedPlan
        : (available.contains('monthly') ? 'monthly' : (available.isNotEmpty ? available.first : null));
  }

  Future<void> _pay() async {
    final offer = _selected;
    if (offer == null || _purchasing || _waitingForNardopay) return;
    setState(() => _purchaseError = null);
    if (_method == 'nardopay') {
      await _payWithNardopay(offer.plan);
    } else {
      await _subscribeWithLemonSqueezy(offer.plan);
    }
  }

  Future<void> _subscribeWithLemonSqueezy(String plan) async {
    setState(() => _purchasing = true);
    try {
      final checkoutUrl = await SubscriptionService.createCheckout(plan);
      final opened = await launchUrl(Uri.parse(checkoutUrl), mode: LaunchMode.externalApplication);
      if (!opened) {
        setState(() => _purchaseError = 'The checkout page couldn\'t be opened. Please try again.');
        return;
      }
      _awaitingCheckoutResult = true;
      _showToast('Finish subscribing on the checkout page, then come back here.');
    } catch (e) {
      setState(() => _purchaseError = _clean(e));
    } finally {
      if (mounted) setState(() => _purchasing = false);
    }
  }

  /// The server creates and prices the pass order; NardoPay's page opens in a new tab; this screen checks the order
  /// until the server has granted the pass. Nothing here marks a payment paid.
  Future<void> _payWithNardopay(String plan) async {
    setState(() => _purchasing = true);
    NardopayOrder order;
    try {
      order = await widget.nardopay.createPremiumPass(plan);
      final link = order.paymentLink;
      if (link == null || !await launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication)) {
        setState(() => _purchaseError = 'The NardoPay page couldn\'t be opened. Please try again.');
        return;
      }
    } catch (e) {
      setState(() => _purchaseError = _clean(e));
      return;
    } finally {
      if (mounted) setState(() => _purchasing = false);
    }
    if (!mounted) return;
    setState(() => _waitingForNardopay = true);
    final status = await waitForNardopayOrder(widget.nardopay, order.orderId, cancelled: () => !mounted);
    if (!mounted) return;
    setState(() => _waitingForNardopay = false);
    switch (status) {
      case 'credited':
        _showToast('VIYO Premium is on');
        Navigator.of(context).pop(true);
      case 'failed':
        setState(() => _purchaseError = 'The payment didn\'t go through, so Premium wasn\'t added.');
      case 'mismatch':
        setState(() => _purchaseError =
            'NardoPay reported a different amount, so Premium wasn\'t added. Please contact support.');
      default:
        _showToast('Still waiting for NardoPay. If you paid, Premium will switch on soon.');
    }
  }

  static String _clean(Object e) => '$e'.replaceFirst(RegExp(r'^Exception:\s*'), '');

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
    if (status != null && status.isSubscribed && !_extending) return _activeMember(status);
    return _sales();
  }

  Widget _sales() {
    final methods = _extending ? _methods.where((m) => m == 'nardopay').toList() : _methods;
    final onSale = methods.isNotEmpty;
    final selected = _selected;
    final busy = _purchasing || _checking || _waitingForNardopay;
    final offers = _offers;
    final monthly = offers.where((o) => o.plan == 'monthly' && o.available).firstOrNull;

    return PurchaseBody(
      bottom: _isAndroid
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                PurchaseButton(
                  label: selected == null
                      ? (onSale ? 'Choose a plan' : 'Not available yet')
                      : (_method == 'nardopay'
                          ? 'Pay ${selected.price} for ${selected.unit}'
                          : 'Subscribe · ${selected.price} / ${selected.unit}'),
                  accent: AppColors.primary,
                  busy: _purchasing,
                  onPressed: selected != null && !busy ? _pay : null,
                ),
                PurchaseFinePrint(!onSale
                    ? 'Premium is paid with money, not coins.'
                    : (_method == 'nardopay'
                        ? 'Paid with money, not coins. One payment, charged in Rwandan francs at today\'s rate. '
                            'It doesn\'t renew: you can add more time whenever you like.'
                        : 'Paid with money, not coins. Renews automatically until you cancel; manage or cancel it '
                            'from your Lemon Squeezy receipt email.')),
              ],
            ),
      children: [
        const SizedBox(height: 8),
        _Hero(extending: _extending),
        const SizedBox(height: 20),
        if (!_extending)
          for (final (icon, title, text) in _benefits) _Benefit(icon: icon, title: title, text: text),
        if (_isAndroid) ...[
          const SizedBox(height: 16),
          const PurchaseNotice(
            tone: NoticeTone.info,
            title: 'Premium isn\'t available in this app',
            message: 'You can keep unlocking episodes with coins.',
          ),
        ] else ...[
          if (methods.length > 1) ...[
            const PurchaseSectionLabel('How you pay'),
            for (final m in methods)
              Padding(
                padding: const EdgeInsets.only(bottom: PurchaseUi.gap),
                child: _MethodTile(
                  method: m,
                  selected: m == _method,
                  enabled: !busy,
                  onTap: () => setState(() => _pickMethod(m)),
                ),
              ),
          ],
          const PurchaseSectionLabel('Choose your plan'),
          if (!onSale) ...[
            const PurchaseNotice(
              tone: NoticeTone.info,
              title: 'Premium subscriptions aren\'t open yet',
              message: 'Plans and prices will appear here as soon as they are. Until then, you can keep unlocking '
                  'episodes with coins.',
            ),
            const SizedBox(height: PurchaseUi.gap),
            for (final plan in _planOrder)
              Padding(
                padding: const EdgeInsets.only(bottom: PurchaseUi.gap),
                child: _PlanCard(
                  offer: _Offer(plan, false, null, '', 'Not available right now'),
                  selected: false,
                  savePercent: null,
                  enabled: false,
                  onTap: () {},
                ),
              ),
          ] else
            for (final offer in offers)
              Padding(
                padding: const EdgeInsets.only(bottom: PurchaseUi.gap),
                child: _PlanCard(
                  offer: offer,
                  selected: offer.plan == _selectedPlan,
                  savePercent: _yearlySaving(offer, monthly),
                  enabled: !busy,
                  onTap: () => setState(() => _selectedPlan = offer.plan),
                ),
              ),
          if (methods.length == 1 && methods.first == 'nardopay')
            const Padding(
              padding: EdgeInsets.only(bottom: PurchaseUi.gap),
              child: _MethodTile(method: 'nardopay', selected: true, enabled: true, single: true),
            ),
          if (_waitingForNardopay)
            const PurchaseNotice(
              tone: NoticeTone.waiting,
              title: 'Waiting for payment confirmation',
              message: 'Finish paying in the NardoPay tab. Premium switches on here once NardoPay confirms it.',
            ),
          if (_checking)
            const PurchaseNotice(
              tone: NoticeTone.waiting,
              title: 'Checking your subscription',
              message: 'This takes a few seconds after you finish paying.',
            ),
          if (_purchaseError != null)
            PurchaseNotice(tone: NoticeTone.error, title: 'Premium not added', message: _purchaseError),
          if (_extending)
            TextButton(onPressed: busy ? null : () => setState(() => _extending = false), child: const Text('Cancel')),
        ],
      ],
    );
  }

  /// "Save N%" for the yearly plan against twelve months of the monthly one (subscriptions) or 365/30 of the 30-day
  /// pass (NardoPay), both real prices in the same currency.
  int? _yearlySaving(_Offer offer, _Offer? monthly) {
    if (offer.plan != 'yearly' || !offer.available || monthly == null) return null;
    if (offer.priceCents == null || monthly.priceCents == null || offer.currency != monthly.currency) return null;
    double yearOfMonthly;
    if (_method == 'nardopay') {
      final o = _options!;
      final y = o.nardopayPasses.firstWhere((p) => p.plan == 'yearly');
      final m = o.nardopayPasses.firstWhere((p) => p.plan == 'monthly');
      yearOfMonthly = m.priceCents * y.days / m.days;
    } else {
      final y = _options!.premiumPlans.firstWhere((p) => p.plan == 'yearly');
      final m = _options!.premiumPlans.firstWhere((p) => p.plan == 'monthly');
      if (y.interval != 'year' || m.interval != 'month' || (y.intervalCount ?? 1) != 1 || (m.intervalCount ?? 1) != 1) {
        return null;
      }
      yearOfMonthly = monthly.priceCents! * 12;
    }
    final saving = (1 - offer.priceCents! / yearOfMonthly) * 100;
    return saving >= 5 ? saving.floor() : null;
  }

  Widget _activeMember(SubscriptionStatus status) {
    final pass = status.provider == 'nardopay';
    final renewsAt = status.renewsAt;
    final endsAt = status.endsAt;
    final canExtend = pass && _methods.contains('nardopay');
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
                pass ? 'Premium pass' : '${_planTitle(status.plan ?? 'monthly')} plan',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
              const Spacer(),
              const PurchaseChip('Active', color: AppColors.success),
            ]),
            if (!pass && renewsAt != null) ...[
              const SizedBox(height: 6),
              Text('Renews ${renewsAt.split('T').first}',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            ] else if (endsAt != null) ...[
              const SizedBox(height: 6),
              Text('Ends ${endsAt.split('T').first}',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            ],
            const SizedBox(height: 12),
            Text(
              pass
                  ? 'Paid once with NardoPay. It doesn\'t renew automatically: add more time before it ends to keep '
                      'watching without coins.'
                  : 'Manage or cancel your subscription from the receipt email Lemon Squeezy sent you.',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.4),
            ),
            if (canExtend) ...[
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => setState(() {
                    _extending = true;
                    _pickMethod('nardopay');
                  }),
                  child: const Text('Add more time'),
                ),
              ),
            ],
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
  final bool extending;
  const _Hero({this.member = false, this.extending = false});

  @override
  Widget build(BuildContext context) {
    final title = member
        ? 'You\'re a Premium member'
        : (extending ? 'Add more Premium time' : 'Unlimited episodes,\nno coins needed');
    final text = member
        ? 'Every episode of every series is unlocked for you.'
        : (extending
            ? 'The time you add starts when your current pass ends.'
            : 'One plan unlocks every drama on VIYO, instead of paying coins episode by episode.');
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
        Text(title,
            textAlign: TextAlign.center, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, height: 1.2)),
        const SizedBox(height: 8),
        Text(text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.45)),
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

/// How each Premium payment method is presented: the provider's own name and how it bills, nothing more.
const _premiumMethodInfo = <String, (String, String, IconData)>{
  'nardopay': ('Mobile money or card', 'NardoPay · one payment, doesn\'t renew', Icons.phone_iphone_rounded),
  'lemonsqueezy': ('Card subscription', 'Lemon Squeezy · renews automatically', Icons.credit_card_rounded),
};

class _MethodTile extends StatelessWidget {
  final String method;
  final bool selected;
  final bool enabled;
  final bool single;
  final VoidCallback? onTap;

  const _MethodTile(
      {required this.method, required this.selected, required this.enabled, this.single = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    final (title, subtitle, icon) = _premiumMethodInfo[method]!;
    return SelectableCard(
      selected: selected,
      enabled: enabled,
      accent: AppColors.primary,
      onTap: single ? null : onTap,
      semanticsLabel: '$title, $subtitle',
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.surfaceBorder),
            ),
            child: Icon(icon, size: 20, color: AppColors.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
              ],
            ),
          ),
          if (!single) SelectionDot(selected: selected, accent: AppColors.primary),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final _Offer offer;
  final bool selected;
  final int? savePercent;
  final bool enabled;
  final VoidCallback onTap;

  const _PlanCard({
    required this.offer,
    required this.selected,
    required this.savePercent,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final price = offer.price;
    final title = _planTitle(offer.plan);
    return SelectableCard(
      selected: selected && offer.available,
      enabled: enabled && offer.available,
      accent: AppColors.primary,
      onTap: onTap,
      semanticsLabel: price != null ? '$title, $price for ${offer.unit}' : '$title, not available',
      child: Row(
        children: [
          SelectionDot(selected: selected && offer.available, accent: AppColors.primary),
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
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    if (savePercent != null) PurchaseChip('Save $savePercent%', color: AppColors.coin),
                  ],
                ),
                const SizedBox(height: 3),
                Text(offer.detail, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (price != null && offer.available)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(price, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                Text('/ ${offer.unit}', style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
              ],
            )
          else
            const PurchaseChip('Not available', color: AppColors.textMuted),
        ],
      ),
    );
  }
}
