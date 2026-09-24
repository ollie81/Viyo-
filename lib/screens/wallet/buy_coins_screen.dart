import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/coin_purchase_service.dart';
import '../../services/google_play_purchase_service.dart';
import '../../services/profile_service.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/viyo_toast.dart';

enum _PaymentProvider { stripe, paystack, flutterwave, lemonsqueezy }

/// Real-money coin purchases. Coins are only ever credited by the
/// backend once the payment provider confirms the charge — this screen
/// never marks a purchase as fulfilled itself.
///
/// Android is a special case: Google Play policy requires any digital
/// good consumed inside an app distributed through Google Play to be
/// sold via Play Billing, not a third-party processor — offering both
/// is itself a policy violation (anti-steering), not just unnecessary.
/// So on Android specifically, this skips straight to Google Play
/// Billing (see google_play_purchase_service.dart) instead of showing
/// the Stripe/Paystack/Flutterwave/Lemon Squeezy picker below, which
/// only web ever sees.
class BuyCoinsScreen extends StatefulWidget {
  const BuyCoinsScreen({super.key});

  @override
  State<BuyCoinsScreen> createState() => _BuyCoinsScreenState();
}

class _BuyCoinsScreenState extends State<BuyCoinsScreen> with WidgetsBindingObserver {
  List<CoinPackage> _packages = [];
  bool _loading = true;
  String? _loadError;
  String? _purchasingPackageId;
  String? _toast;

  // Set while waiting for the user to come back from a Paystack/
  // Flutterwave checkout opened in the system browser — there's no
  // callback into the app from a plain external browser tab, so app
  // resume (didChangeAppLifecycleState) is the signal to start
  // polling the balance, same as Stripe's payment sheet closing does.
  int? _hostedCheckoutExpectedCoins;

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
    if (state != AppLifecycleState.resumed) return;
    final expected = _hostedCheckoutExpectedCoins;
    if (expected == null) return;
    _hostedCheckoutExpectedCoins = null;
    final userId = SupabaseService.currentUserId;
    if (userId == null) return;
    _showToast('Checking for your coins…');
    _waitForCredit(userId, expected);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final packages = await CoinPurchaseService.getPackages();
      if (!mounted) return;
      setState(() {
        _packages = packages;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = 'Could not load coin packages. Pull to try again.';
        _loading = false;
      });
    }
  }

  void _showToast(String msg) {
    setState(() => _toast = msg);
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _toast = null);
    });
  }

  static bool get _isAndroidNative => !kIsWeb && Platform.isAndroid;

  Future<void> _buy(CoinPackage package) async {
    if (_purchasingPackageId != null) return;

    if (_isAndroidNative) {
      await _buyWithGooglePlay(package);
      return;
    }

    final provider = await _pickProvider();
    if (provider == null) return;

    switch (provider) {
      case _PaymentProvider.stripe:
        await _buyWithStripe(package);
        break;
      case _PaymentProvider.paystack:
        await _buyWithHostedCheckout(package, provider: 'paystack');
        break;
      case _PaymentProvider.flutterwave:
        await _buyWithHostedCheckout(package, provider: 'flutterwave');
        break;
      case _PaymentProvider.lemonsqueezy:
        await _buyWithHostedCheckout(package, provider: 'lemonsqueezy');
        break;
    }
  }

  Future<_PaymentProvider?> _pickProvider() {
    return showModalBottomSheet<_PaymentProvider>(
      context: context,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Pay with', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              _ProviderTile(
                label: 'Card (Stripe)',
                icon: Icons.credit_card,
                onTap: () => Navigator.of(ctx).pop(_PaymentProvider.stripe),
              ),
              _ProviderTile(
                label: 'Paystack',
                icon: Icons.account_balance_wallet_outlined,
                onTap: () => Navigator.of(ctx).pop(_PaymentProvider.paystack),
              ),
              _ProviderTile(
                label: 'Flutterwave',
                icon: Icons.payments_outlined,
                onTap: () => Navigator.of(ctx).pop(_PaymentProvider.flutterwave),
              ),
              _ProviderTile(
                label: 'Lemon Squeezy',
                icon: Icons.storefront_outlined,
                onTap: () => Navigator.of(ctx).pop(_PaymentProvider.lemonsqueezy),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _buyWithStripe(CoinPackage package) async {
    final userId = SupabaseService.currentUserId;
    if (userId == null) return;

    setState(() => _purchasingPackageId = package.id);
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

      // Stripe has confirmed the charge — the backend webhook credits
      // the balance asynchronously, usually within a second or two.
      _showToast('Payment successful! Adding your coins…');
      await _waitForCredit(userId, package.coins);
    } on StripeException catch (e) {
      final code = e.error.code;
      if (code != FailureCode.Canceled) {
        _showToast(e.error.localizedMessage ?? 'Payment failed. Please try again.');
      }
    } catch (e) {
      _showToast('Purchase failed: $e');
    } finally {
      if (mounted) setState(() => _purchasingPackageId = null);
    }
  }

  /// Paystack, Flutterwave and Lemon Squeezy all check out on a hosted
  /// page rather than an in-app sheet — this opens it in the system
  /// browser and relies on app-resume (didChangeAppLifecycleState
  /// above) to know when to start polling for the credit, since
  /// there's no direct callback from an external browser tab back into
  /// the app.
  Future<void> _buyWithHostedCheckout(CoinPackage package, {required String provider}) async {
    setState(() => _purchasingPackageId = package.id);
    try {
      final HostedCheckout checkout;
      switch (provider) {
        case 'paystack':
          checkout = await CoinPurchaseService.initializePaystack(package.id);
          break;
        case 'flutterwave':
          checkout = await CoinPurchaseService.initializeFlutterwave(package.id);
          break;
        default:
          checkout = await CoinPurchaseService.initializeLemonSqueezy(package.id);
      }

      final opened = await launchUrl(
        Uri.parse(checkout.url),
        mode: LaunchMode.externalApplication,
      );
      if (!opened) {
        _showToast('Could not open the checkout page.');
        return;
      }
      _hostedCheckoutExpectedCoins = checkout.coins;
      _showToast('Complete your payment in the browser, then come back here.');
    } catch (e) {
      _showToast('Purchase failed: $e');
    } finally {
      if (mounted) setState(() => _purchasingPackageId = null);
    }
  }

  /// Android-only purchase path — Google Play Billing handles both the
  /// payment UI and the "did it actually succeed" confirmation itself,
  /// so unlike Stripe/the hosted-checkout providers there's no separate
  /// polling step: GooglePlayPurchaseService.buy only resolves once the
  /// backend has already verified the purchase with Google and credited
  /// the coins.
  Future<void> _buyWithGooglePlay(CoinPackage package) async {
    setState(() => _purchasingPackageId = package.id);
    try {
      final coins = await GooglePlayPurchaseService.buy(package.id);
      if (!mounted) return;
      _showToast('+$coins coins added! 🪙');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      if (!e.toString().contains('canceled')) {
        _showToast('Purchase failed: $e');
      }
    } finally {
      if (mounted) setState(() => _purchasingPackageId = null);
    }
  }

  Future<void> _waitForCredit(String userId, int expectedCoins) async {
    final before = (await ProfileService.getProfile(userId)).pointsBalance;
    for (var i = 0; i < 6; i++) {
      await Future.delayed(const Duration(seconds: 2));
      final profile = await ProfileService.getProfile(userId);
      if (profile.pointsBalance >= before + expectedCoins) {
        if (mounted) {
          _showToast('+$expectedCoins coins added! 🪙');
          Navigator.of(context).pop(true);
        }
        return;
      }
    }
    if (mounted) {
      _showToast("Payment received — coins will appear shortly if they haven't already.");
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: AppColors.background, title: const Text('Buy Coins')),
      body: Stack(
        children: [
          _loading
              ? const _BuyCoinsSkeleton()
              : _loadError != null
                  ? RefreshIndicator(
                      onRefresh: _load,
                      color: AppColors.primary,
                      child: ListView(
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 100),
                            child: Center(
                              child: Text(_loadError!, style: const TextStyle(color: AppColors.textMuted)),
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                      children: [
                        const Text(
                          'Coins power AI features, post boosts, and Discover Spotlight.',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: 16),
                        ..._packages.map((p) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _PackageCard(
                                package: p,
                                purchasing: _purchasingPackageId == p.id,
                                disabled: _purchasingPackageId != null,
                                onTap: () => _buy(p),
                              ),
                            )),
                      ],
                    ),
          if (_toast != null) ViyoToast(message: _toast!),
        ],
      ),
    );
  }
}

class _PackageCard extends StatelessWidget {
  final CoinPackage package;
  final bool purchasing;
  final bool disabled;
  final VoidCallback onTap;

  const _PackageCard({
    required this.package,
    required this.purchasing,
    required this.disabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: disabled ? null : onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: AppTheme.glowCard(glowColor: AppColors.coin, glowOpacity: 0.14),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                gradient: AppGradients.coin,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.monetization_on_rounded, color: AppColors.background),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(package.label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(package.priceDisplay, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                ],
              ),
            ),
            SizedBox(
              width: 72,
              child: purchasing
                  ? const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.coin),
                      ),
                    )
                  : ElevatedButton(
                      onPressed: disabled ? null : onTap,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.coin,
                        foregroundColor: AppColors.background,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      child: const Text('Buy', style: TextStyle(fontSize: 13)),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProviderTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _ProviderTile({required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: AppColors.coin, size: 22),
            const SizedBox(width: 14),
            Text(label, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
            const Spacer(),
            const Icon(Icons.chevron_right, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

class _BuyCoinsSkeleton extends StatelessWidget {
  const _BuyCoinsSkeleton();

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppColors.surface,
      highlightColor: AppColors.surfaceBorder,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 4,
        itemBuilder: (_, __) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Container(
            height: 82,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
          ),
        ),
      ),
    );
  }
}
