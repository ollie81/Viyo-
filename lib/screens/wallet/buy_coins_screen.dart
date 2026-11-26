import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/checkout_options_service.dart';
import '../../services/coin_purchase_service.dart';
import '../../services/nardopay_service.dart';
import '../../services/profile_service.dart';
import '../../services/rewarded_ad_service.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/purchase_ui.dart';
import '../../widgets/viyo_toast.dart';
import '../mission_screen.dart';

/// Real-money coin purchases. Coins are only ever credited by the backend once the payment provider confirms the
/// charge; this screen never marks a purchase as fulfilled itself.
///
/// Which payment methods appear comes from the server (GET /api/v1/checkout/options), which reports a provider only
/// when its checkout AND its webhook verification are configured, filtered by what this platform can run
/// (coinMethodsFor). With no live method the packages are still shown with their real prices, and the screen says
/// plainly that buying isn't open; nothing pretends to work.
///
/// Android is a special case: Google Play policy requires any digital good consumed inside an app distributed
/// through Google Play to be sold via Play Billing, not a third-party processor (offering both, or linking out to
/// pay on the web, is itself a policy violation). So Android shows no purchase option at all, only the free ways to
/// earn coins (ads, missions, daily check-in), until real Play Billing gets built. See GooglePlayPurchaseService for
/// that path, left in place unused.
class BuyCoinsScreen extends StatefulWidget {
  /// For tests: where the options come from, the platform, and the NardoPay API.
  final Future<CheckoutOptions> Function()? loadOptions;
  final PurchasePlatform? platform;
  final NardopayApi nardopay;

  const BuyCoinsScreen({super.key, this.loadOptions, this.platform, this.nardopay = const NardopayApi()});

  @override
  State<BuyCoinsScreen> createState() => _BuyCoinsScreenState();
}

/// How each live method is presented. Only the provider's own name: no payment types are claimed for it.
const _methodInfo = <String, (String, String, IconData)>{
  'nardopay': ('Mobile money or card', 'Checkout by NardoPay', Icons.phone_iphone_rounded),
  'stripe': ('Card', 'Secure card payment by Stripe', Icons.credit_card_rounded),
  'paystack': ('Paystack', 'Checkout by Paystack', Icons.account_balance_wallet_outlined),
  'flutterwave': ('Flutterwave', 'Checkout by Flutterwave', Icons.payments_outlined),
};

class _BuyCoinsScreenState extends State<BuyCoinsScreen> with WidgetsBindingObserver {
  List<CoinPackage> _packages = [];
  List<String> _methods = [];
  String? _packageId;
  String? _method;
  bool _loading = true;
  String? _loadError;
  bool _purchasing = false;
  String? _toast;
  String? _purchaseError;

  // Set while waiting for the user to come back from a hosted checkout (Paystack, Flutterwave)
  // opened in the browser: there's no callback from an external tab, so app resume (didChangeAppLifecycleState) is
  // the signal to start checking the balance, same as Stripe's payment sheet closing does.
  int? _hostedCheckoutExpectedCoins;

  bool _watchingAd = false;
  bool _waitingForNardopay = false;
  bool _checkingBalance = false;

  PurchasePlatform get _platform => widget.platform ?? currentPurchasePlatform;
  bool get _isAndroid => _platform == PurchasePlatform.android;

  CoinPackage? get _selected {
    for (final p in _packages) {
      if (p.id == _packageId) return p;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // No purchase UI on Android (see the class comment): nothing to load.
    if (_isAndroid) {
      _loading = false;
    } else {
      _load();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final expected = _hostedCheckoutExpectedCoins;
    if (expected == null) return;
    _hostedCheckoutExpectedCoins = null;
    final userId = SupabaseService.currentUserId;
    if (userId == null) return;
    _waitForCredit(userId, expected);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final options = await (widget.loadOptions ?? CheckoutOptionsService.fetch)();
      if (!mounted) return;
      final methods = coinMethodsFor(_platform, options.coinProviders).where(_methodInfo.containsKey).toList();
      setState(() {
        _packages = options.packages;
        _methods = methods;
        _packageId = _packageId ?? (options.packages.isNotEmpty ? options.packages.first.id : null);
        _method = methods.contains(_method) ? _method : (methods.isNotEmpty ? methods.first : null);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = 'Check your connection and try again.';
        _loading = false;
      });
    }
  }

  void _showToast(String msg) {
    setState(() => _toast = msg);
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _toast == msg) setState(() => _toast = null);
    });
  }

  Future<void> _pay() async {
    final package = _selected;
    final method = _method;
    if (package == null || method == null || _purchasing || _waitingForNardopay) return;
    setState(() => _purchaseError = null);
    switch (method) {
      case 'stripe':
        await _buyWithStripe(package);
      case 'nardopay':
        await _buyWithNardopay(package);
      default:
        await _buyWithHostedCheckout(package, provider: method);
    }
  }

  Future<void> _buyWithStripe(CoinPackage package) async {
    final userId = SupabaseService.currentUserId;
    if (userId == null) return;

    setState(() => _purchasing = true);
    try {
      final intent = await CoinPurchaseService.createIntent(package.id);

      Stripe.publishableKey = intent.publishableKey;
      await Stripe.instance.applySettings();

      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: intent.clientSecret,
          merchantDisplayName: 'Viyo',
        ),
      );
      await Stripe.instance.presentPaymentSheet();

      // Stripe has confirmed the charge: the backend webhook credits the balance, usually within a second or two.
      await _waitForCredit(userId, package.coins);
    } on StripeException catch (e) {
      if (e.error.code != FailureCode.Canceled) {
        setState(() => _purchaseError = e.error.localizedMessage ?? 'The payment didn\'t go through. Please try again.');
      }
    } catch (e) {
      setState(() => _purchaseError = _clean(e));
    } finally {
      if (mounted) setState(() => _purchasing = false);
    }
  }

  /// Paystack and Flutterwave check out on a hosted page: this opens it and relies on app resume
  /// (didChangeAppLifecycleState above) to know when to start checking for the credit.
  Future<void> _buyWithHostedCheckout(CoinPackage package, {required String provider}) async {
    setState(() => _purchasing = true);
    try {
      final HostedCheckout checkout;
      switch (provider) {
        case 'paystack':
          checkout = await CoinPurchaseService.initializePaystack(package.id);
        default:
          checkout = await CoinPurchaseService.initializeFlutterwave(package.id);
      }
      final opened = await launchUrl(Uri.parse(checkout.url), mode: LaunchMode.externalApplication);
      if (!opened) {
        setState(() => _purchaseError = 'The checkout page couldn\'t be opened. Please try again.');
        return;
      }
      _hostedCheckoutExpectedCoins = checkout.coins;
      _showToast('Finish paying on the checkout page, then come back here.');
    } catch (e) {
      setState(() => _purchaseError = _clean(e));
    } finally {
      if (mounted) setState(() => _purchasing = false);
    }
  }

  /// NardoPay (web only): the server creates and prices the order, NardoPay's page opens in a new tab, and this
  /// screen checks the order until the server has credited it. Nothing here marks a purchase paid.
  Future<void> _buyWithNardopay(CoinPackage package) async {
    if (_waitingForNardopay) return;
    setState(() => _purchasing = true);
    NardopayOrder order;
    try {
      order = await widget.nardopay.create(package.id);
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
        _showToast('+${order.coins} coins added');
        Navigator.of(context).pop(true);
      case 'failed':
        setState(() => _purchaseError = 'The payment didn\'t go through, so no coins were added.');
      case 'mismatch':
        setState(() => _purchaseError =
            'NardoPay reported a different amount, so no coins were added. Please contact support.');
      default:
        _showToast('Still waiting for NardoPay. If you paid, your coins will appear soon.');
    }
  }

  static String _clean(Object e) => '$e'.replaceFirst(RegExp(r'^Exception:\s*'), '');

  /// Android's only coin-earning action on this screen (same RewardedAdService flow as the wallet's button).
  Future<void> _watchAd() async {
    setState(() => _watchingAd = true);
    try {
      final coins = await RewardedAdService.showAndClaim();
      _showToast(coins != null ? '+$coins coins, thanks for watching' : 'No ad available right now. Try again soon.');
    } catch (e) {
      _showToast('$e');
    } finally {
      if (mounted) setState(() => _watchingAd = false);
    }
  }

  Future<void> _waitForCredit(String userId, int expectedCoins) async {
    setState(() => _checkingBalance = true);
    try {
      final before = (await ProfileService.getProfile(userId)).pointsBalance;
      for (var i = 0; i < 6; i++) {
        await Future.delayed(const Duration(seconds: 2));
        final profile = await ProfileService.getProfile(userId);
        if (profile.pointsBalance >= before + expectedCoins) {
          if (mounted) {
            _showToast('+$expectedCoins coins added');
            Navigator.of(context).pop(true);
          }
          return;
        }
      }
      if (mounted) {
        _showToast("Payment received. Your coins will appear shortly if they haven't already.");
        Navigator.of(context).pop(true);
      }
    } finally {
      if (mounted) setState(() => _checkingBalance = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(backgroundColor: AppColors.background, title: const Text('Buy Coins')),
      body: Stack(
        children: [
          if (_isAndroid)
            _AndroidNoPurchaseView(
              watchingAd: _watchingAd,
              onWatchAd: _watchAd,
              onOpenMissions: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const MissionsScreen()),
              ),
            )
          else if (_loading)
            const PurchaseSkeleton()
          else if (_loadError != null)
            PurchaseBody(children: [
              const SizedBox(height: 24),
              PurchaseNotice(
                tone: NoticeTone.error,
                title: 'Coin packages couldn\'t be loaded',
                message: _loadError,
                action: OutlinedButton(onPressed: _load, child: const Text('Try again')),
              ),
            ])
          else
            _storefront(),
          if (_toast != null) ViyoToast(message: _toast!),
        ],
      ),
    );
  }

  Widget _storefront() {
    final selected = _selected;
    final canPay = selected != null && _method != null;
    final busy = _purchasing || _waitingForNardopay || _checkingBalance;
    final baseRate = _packages.isEmpty
        ? 0.0
        : _packages.map((p) => p.coins / p.usdCents).reduce((a, b) => a < b ? a : b);

    return PurchaseBody(
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PurchaseButton(
            label: canPay ? 'Pay ${selected.priceDisplay}' : (_methods.isEmpty ? 'Purchases not available' : 'Choose a package'),
            accent: AppColors.coin,
            busy: _purchasing,
            onPressed: canPay && !busy ? _pay : null,
          ),
          PurchaseFinePrint(_methods.isEmpty
              ? 'Prices in US dollars.'
              : 'Prices in US dollars. Coins are added as soon as the payment is confirmed.'),
        ],
      ),
      children: [
        const Text('Get coins', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, height: 1.2)),
        const SizedBox(height: 6),
        const Text(
          'Coins unlock episodes and power AI features, post boosts and Discover Spotlight.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.45),
        ),
        const PurchaseSectionLabel('Choose a package'),
        LayoutBuilder(builder: (context, c) {
          final twoColumns = c.maxWidth >= 520;
          final width = twoColumns ? (c.maxWidth - PurchaseUi.gap) / 2 : c.maxWidth;
          return Wrap(
            spacing: PurchaseUi.gap,
            runSpacing: PurchaseUi.gap,
            children: [
              for (final p in _packages)
                SizedBox(
                  width: width,
                  child: _PackageCard(
                    package: p,
                    bonusPercent: baseRate == 0 ? 0 : ((p.coins / p.usdCents) / baseRate - 1) * 100,
                    selected: p.id == _packageId,
                    enabled: !busy,
                    onTap: () => setState(() => _packageId = p.id),
                  ),
                ),
            ],
          );
        }),
        const PurchaseSectionLabel('Payment method'),
        if (_methods.isEmpty)
          const PurchaseNotice(
            tone: NoticeTone.info,
            title: 'Buying coins isn\'t available right now',
            message: 'You can still earn coins for free with daily check-ins and missions.',
          )
        else
          for (final m in _methods)
            Padding(
              padding: const EdgeInsets.only(bottom: PurchaseUi.gap),
              child: _MethodTile(
                method: m,
                selected: m == _method,
                single: _methods.length == 1,
                enabled: !busy,
                onTap: () => setState(() => _method = m),
              ),
            ),
        if (_waitingForNardopay || _checkingBalance) ...[
          const SizedBox(height: 4),
          PurchaseNotice(
            tone: NoticeTone.waiting,
            title: 'Waiting for payment confirmation',
            message: _waitingForNardopay
                ? 'Finish paying in the NardoPay tab. Your coins appear here once NardoPay confirms the payment.'
                : 'Checking for your coins…',
          ),
        ],
        if (_purchaseError != null) ...[
          const SizedBox(height: 4),
          PurchaseNotice(tone: NoticeTone.error, title: 'Payment not completed', message: _purchaseError),
        ],
      ],
    );
  }
}

class _PackageCard extends StatelessWidget {
  final CoinPackage package;
  final double bonusPercent;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _PackageCard({
    required this.package,
    required this.bonusPercent,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bonus = bonusPercent.round();
    return SelectableCard(
      selected: selected,
      enabled: enabled,
      accent: AppColors.coin,
      onTap: onTap,
      semanticsLabel: '${package.label}, ${package.priceDisplay}',
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(gradient: AppGradients.coin, shape: BoxShape.circle),
            child: const Icon(Icons.monetization_on_rounded, color: AppColors.background, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _groupedCoins(package.coins),
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, height: 1.1),
                ),
                const SizedBox(height: 2),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Text('coins', style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
                    if (bonus >= 5) PurchaseChip('+$bonus% coins', color: AppColors.coin),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(package.priceDisplay, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(width: 14),
          SelectionDot(selected: selected, accent: AppColors.coin),
        ],
      ),
    );
  }
}

/// 3000 -> "3,000".
String _groupedCoins(int n) {
  final s = n.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

class _MethodTile extends StatelessWidget {
  final String method;
  final bool selected;
  final bool single;
  final bool enabled;
  final VoidCallback onTap;

  const _MethodTile({
    required this.method,
    required this.selected,
    required this.single,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final (title, subtitle, icon) = _methodInfo[method]!;
    return SelectableCard(
      selected: selected,
      enabled: enabled,
      accent: AppColors.coin,
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
            child: Icon(icon, size: 20, color: AppColors.coin),
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
          if (!single) SelectionDot(selected: selected, accent: AppColors.coin),
        ],
      ),
    );
  }
}

class _AndroidNoPurchaseView extends StatelessWidget {
  final bool watchingAd;
  final VoidCallback onWatchAd;
  final VoidCallback onOpenMissions;

  const _AndroidNoPurchaseView({
    required this.watchingAd,
    required this.onWatchAd,
    required this.onOpenMissions,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: AppTheme.card(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.monetization_on_outlined, color: AppColors.coin, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text('Buying coins isn\'t available here yet',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Watch ads, complete missions, or check in daily to earn coins for free in the meantime.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: watchingAd ? null : onWatchAd,
                  icon: const Icon(Icons.smart_display_outlined, size: 18),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.coin,
                    foregroundColor: AppColors.background,
                  ),
                  label: Text(watchingAd ? 'Loading ad...' : 'Watch Ad for Free Coins'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: onOpenMissions,
                  child: const Text('See Missions'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

