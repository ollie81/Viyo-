import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:shimmer/shimmer.dart';
import '../../services/coin_purchase_service.dart';
import '../../services/profile_service.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/viyo_toast.dart';

/// Real-money coin purchases via Stripe's Payment Sheet. Coins are only
/// ever credited by the backend once Stripe confirms the charge (see
/// payments.py's webhook) — this screen never marks a purchase as
/// fulfilled itself, it just starts checkout and then polls the balance
/// for the credit to land, since the webhook may lag the sheet closing
/// by a second or two.
class BuyCoinsScreen extends StatefulWidget {
  const BuyCoinsScreen({super.key});

  @override
  State<BuyCoinsScreen> createState() => _BuyCoinsScreenState();
}

class _BuyCoinsScreenState extends State<BuyCoinsScreen> {
  List<CoinPackage> _packages = [];
  bool _loading = true;
  String? _loadError;
  String? _purchasingPackageId;
  String? _toast;

  @override
  void initState() {
    super.initState();
    _load();
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

  Future<void> _buy(CoinPackage package) async {
    final userId = SupabaseService.currentUserId;
    if (userId == null || _purchasingPackageId != null) return;

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
