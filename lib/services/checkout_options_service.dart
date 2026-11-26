import 'dart:convert';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:http/http.dart' as http;
import '../constants/supabase_constants.dart';
import 'coin_purchase_service.dart';

/// Where the app is running, for what it may sell there.
enum PurchasePlatform { web, android, other }

PurchasePlatform get currentPurchasePlatform {
  if (kIsWeb) return PurchasePlatform.web;
  return defaultTargetPlatform == TargetPlatform.android ? PurchasePlatform.android : PurchasePlatform.other;
}

/// The coin payment methods this platform can actually run, out of those the server reports as live.
///
/// * Android: none. Google Play policy requires Play Billing for digital goods, so the Android app sells nothing.
/// * Web: everything live except Stripe, whose in-app payment sheet isn't built for the web app.
/// * Other native platforms: the hosted checkouts and Stripe, not NardoPay (web-only by design).
/// Lemon Squeezy is never offered (VIYO no longer sells through it), whatever the server says.
List<String> coinMethodsFor(PurchasePlatform platform, List<String> live) {
  switch (platform) {
    case PurchasePlatform.android:
      return const [];
    case PurchasePlatform.web:
      return live.where((p) => p != 'stripe' && p != 'lemonsqueezy').toList();
    case PurchasePlatform.other:
      return live.where((p) => p != 'nardopay' && p != 'lemonsqueezy').toList();
  }
}

/// One Premium plan as the server reports it. A price is shown only when the server read a real one.
class PremiumPlan {
  final String plan; // weekly | monthly | yearly
  final bool available;
  final int? priceCents;
  final String? currency;
  final String? interval; // day | week | month | year
  final int? intervalCount;
  final String? reason;

  const PremiumPlan({
    required this.plan,
    required this.available,
    this.priceCents,
    this.currency,
    this.interval,
    this.intervalCount,
    this.reason,
  });

  factory PremiumPlan.fromJson(Map<String, dynamic> j) => PremiumPlan(
        plan: j['plan'] as String,
        available: j['available'] == true && j['price_cents'] is num,
        priceCents: (j['price_cents'] as num?)?.toInt(),
        currency: j['currency'] as String?,
        interval: j['interval'] as String?,
        intervalCount: (j['interval_count'] as num?)?.toInt(),
        reason: j['reason'] as String?,
      );

  String get title => switch (plan) { 'weekly' => 'Weekly', 'yearly' => 'Yearly', _ => 'Monthly' };

  /// "$5.99", or the currency code for anything but USD ("EUR 5.99").
  String? get priceLabel {
    final c = priceCents;
    if (!available || c == null) return null;
    final amount = (c / 100).toStringAsFixed(2);
    return (currency ?? 'USD') == 'USD' ? '\$$amount' : '$currency $amount';
  }

  /// "week", "month", "3 months"...
  String get periodLabel {
    final unit = interval ?? switch (plan) { 'weekly' => 'week', 'yearly' => 'year', _ => 'month' };
    final n = intervalCount ?? 1;
    return n == 1 ? unit : '$n ${unit}s';
  }
}

class CheckoutOptions {
  final List<String> coinProviders;
  final List<CoinPackage> packages;
  final List<PremiumPlan> premiumPlans;

  const CheckoutOptions({required this.coinProviders, required this.packages, required this.premiumPlans});

  /// Premium is sold through NardoPay subscriptions, on the web only.
  bool get premiumOnSale => currentPurchasePlatform == PurchasePlatform.web && premiumPlans.any((p) => p.available);

  factory CheckoutOptions.fromJson(Map<String, dynamic> j) {
    final coins = (j['coins'] as Map?)?.cast<String, dynamic>() ?? const {};
    final premium = (j['premium'] as Map?)?.cast<String, dynamic>() ?? const {};
    return CheckoutOptions(
      coinProviders: [for (final p in (coins['providers'] as List? ?? const [])) '$p'],
      packages: [
        for (final p in (coins['packages'] as List? ?? const [])) CoinPackage.fromJson((p as Map).cast<String, dynamic>())
      ],
      premiumPlans: [
        for (final p in (premium['plans'] as List? ?? const [])) PremiumPlan.fromJson((p as Map).cast<String, dynamic>())
      ],
    );
  }
}

/// GET /api/v1/checkout/options: which real-money checkouts are genuinely live (the server checks each provider's
/// checkout AND webhook settings, and reads Premium prices from the provider). Never guessed in the app.
class CheckoutOptionsService {
  /// The last answer, for places that can't wait for a request (e.g. the episode lock's Premium link).
  static CheckoutOptions? last;

  static Future<CheckoutOptions> fetch() async {
    final res = await http
        .get(Uri.parse('${AiBackendConstants.baseUrl}/api/v1/checkout/options'))
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) throw Exception('Could not load prices (${res.statusCode}).');
    final options = CheckoutOptions.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
    last = options;
    return options;
  }
}
