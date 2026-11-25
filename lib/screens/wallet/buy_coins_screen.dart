import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/coin_purchase_service.dart';
import '../../services/nardopay_service.dart';
import '../../services/rewarded_ad_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/viyo_toast.dart';
import '../mission_screen.dart';

/// Real-money coin purchases, on the web through NardoPay (mobile money or card) only. Coins are only ever credited
/// by the backend once NardoPay's signed confirmation arrives; this screen never marks a purchase as fulfilled itself.
/// While NardoPay checkout is off, the packages are shown with a short "opening soon" note and no Buy button works.
///
/// Android is a special case: Google Play policy requires any digital
/// good consumed inside an app distributed through Google Play to be
/// sold via Play Billing, not a third-party processor — offering both
/// is itself a policy violation (anti-steering), and so is just
/// linking out to pay on the web instead, unless enrolled in Google's
/// separate (region-limited, still revenue-shared) External Offers
/// program. Rather than risk that, Android shows no purchase option
/// at all — only the free ways to earn coins (ads, missions, daily
/// check-in) — until real Play Billing gets built. See
/// GooglePlayPurchaseService for that path, left in place unused.
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

  bool _watchingAd = false;

  // NardoPay (web only): offered when the server says checkout is available. The order is created and priced on the
  // server; its status is checked until the server has credited it after NardoPay's signed confirmation.
  static const _nardopay = NardopayApi();
  bool _nardopayAvailable = false;
  bool _waitingForNardopay = false;

  @override
  void initState() {
    super.initState();
    // No purchase UI on Android (see module comment) — nothing to load.
    if (_isAndroidNative) {
      _loading = false;
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final packages = await CoinPurchaseService.getPackages();
      // Web only: the Android app keeps Google Play's rules (see the class comment) and never offers NardoPay.
      final nardopay = kIsWeb && await _nardopay.available();
      if (!mounted) return;
      setState(() {
        _packages = packages;
        _nardopayAvailable = nardopay;
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

  bool get _canBuy => kIsWeb && _nardopayAvailable;

  /// NardoPay (web only): the server creates and prices the order, NardoPay's page opens in a new tab, and this
  /// screen checks the order until the server has credited it. Nothing here marks a purchase paid.
  Future<void> _buyWithNardopay(CoinPackage package) async {
    if (!kIsWeb || _waitingForNardopay) return;
    setState(() => _purchasingPackageId = package.id);
    NardopayOrder order;
    try {
      order = await _nardopay.create(package.id);
      final link = order.paymentLink;
      if (link == null || !await launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication)) {
        _showToast('Could not open the NardoPay page.');
        return;
      }
    } catch (e) {
      _showToast('$e'.replaceFirst('Exception: ', ''));
      return;
    } finally {
      if (mounted) setState(() => _purchasingPackageId = null);
    }
    if (!mounted) return;
    setState(() => _waitingForNardopay = true);
    _showToast('Pay ${order.usdCents > 0 ? order.usdLabel : 'the amount shown'} in the NardoPay tab. Your coins appear here once it\'s confirmed.');
    final status = await waitForNardopayOrder(_nardopay, order.orderId, cancelled: () => !mounted);
    if (!mounted) return;
    setState(() => _waitingForNardopay = false);
    switch (status) {
      case 'credited':
        _showToast('+${order.coins} coins added! 🪙');
        Navigator.of(context).pop(true);
        break;
      case 'failed':
        _showToast('The payment didn\'t go through. You weren\'t charged for coins.');
        break;
      case 'mismatch':
        _showToast('NardoPay reported a different amount, so no coins were added. Contact support.');
        break;
      default:
        _showToast('Still waiting for NardoPay. If you paid, your coins will appear soon.');
    }
  }

  /// Android's only coin-earning action on this screen — same
  /// RewardedAdService flow as the wallet screen's own "Watch Ad for
  /// Free Coins" button.
  Future<void> _watchAd() async {
    setState(() => _watchingAd = true);
    try {
      final coins = await RewardedAdService.showAndClaim();
      if (coins != null) {
        _showToast('+$coins coins — thanks for watching! 🎬');
      } else {
        _showToast('No ad available right now — try again in a bit');
      }
    } catch (e) {
      _showToast('$e');
    } finally {
      if (mounted) setState(() => _watchingAd = false);
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
                  : _isAndroidNative
                      ? _AndroidNoPurchaseView(
                          watchingAd: _watchingAd,
                          onWatchAd: _watchAd,
                          onOpenMissions: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const MissionsScreen()),
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
                            if (!_canBuy) ...[
                              const _OpeningSoonNote(),
                              const SizedBox(height: 16),
                            ],
                            ..._packages.map((p) => Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: _PackageCard(
                                    package: p,
                                    purchasing: _purchasingPackageId == p.id,
                                    available: _canBuy,
                                    disabled: _purchasingPackageId != null || _waitingForNardopay,
                                    onTap: () => _buyWithNardopay(p),
                                  ),
                                )),
                            if (_canBuy) const _CheckoutNote(),
                          ],
                        ),
          if (_toast != null) ViyoToast(message: _toast!),
        ],
      ),
    );
  }
}

/// What Android sees on this screen instead of a purchase flow — no
/// digital-good purchase UI at all (see this file's module comment),
/// just the free ways to earn coins that already exist elsewhere in
/// the app.
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
                  Text('Buying coins isn\'t available here yet', style: TextStyle(fontWeight: FontWeight.w700)),
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

class _PackageCard extends StatelessWidget {
  final CoinPackage package;
  final bool purchasing;
  final bool available;
  final bool disabled;
  final VoidCallback onTap;

  const _PackageCard({
    required this.package,
    required this.purchasing,
    required this.available,
    required this.disabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: disabled || !available ? null : onTap,
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
                  : available
                      ? ElevatedButton(
                          onPressed: disabled ? null : onTap,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.coin,
                            foregroundColor: AppColors.background,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                          child: const Text('Buy', style: TextStyle(fontSize: 13)),
                        )
                      : const Center(
                          child: Text('Soon',
                              style: TextStyle(color: AppColors.textMuted, fontSize: 12.5, fontWeight: FontWeight.w600)),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Under the packages while checkout is open: how the buyer pays.
class _CheckoutNote extends StatelessWidget {
  const _CheckoutNote();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.lock_outline, size: 14, color: AppColors.textMuted),
          SizedBox(width: 6),
          Flexible(
            child: Text(
              'Pay with mobile money or card. Secure checkout by NardoPay.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

/// Above the packages while checkout is off.
class _OpeningSoonNote extends StatelessWidget {
  const _OpeningSoonNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.card(),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.schedule_rounded, size: 18, color: AppColors.coin),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Buying coins opens soon, with mobile money or card. Until then, earn free coins with daily '
              'check-ins and missions.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
            ),
          ),
        ],
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
