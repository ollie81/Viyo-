import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants/supabase_constants.dart';
import 'supabase_service.dart';

/// A coin package the backend is willing to sell — id, coin amount, and
/// USD price all come from the server (payments.py's COIN_PACKAGES) so
/// a price change never needs a client release, and so this app never
/// sends a price/coin amount to Stripe itself.
class CoinPackage {
  final String id;
  final int coins;
  final int usdCents;
  final String label;

  CoinPackage({
    required this.id,
    required this.coins,
    required this.usdCents,
    required this.label,
  });

  factory CoinPackage.fromJson(Map<String, dynamic> json) => CoinPackage(
        id: json['id'] as String,
        coins: (json['coins'] as num).toInt(),
        usdCents: (json['usd_cents'] as num).toInt(),
        label: json['label'] as String,
      );

  String get priceDisplay => '\$${(usdCents / 100).toStringAsFixed(2)}';
}

/// Result of starting a purchase — everything the payment sheet needs.
class PurchaseIntent {
  final String clientSecret;
  final String publishableKey;
  final int amountUsdCents;
  final int coins;

  PurchaseIntent({
    required this.clientSecret,
    required this.publishableKey,
    required this.amountUsdCents,
    required this.coins,
  });
}

/// Buying coins with real money, via Stripe. Coins are only ever
/// credited by the backend's webhook once Stripe confirms the charge —
/// this client only ever starts checkout and presents Stripe's Payment
/// Sheet; it never marks a purchase as fulfilled itself.
class CoinPurchaseService {
  static Future<Map<String, String>> _headers() async {
    final token = SupabaseService.client.auth.currentSession?.accessToken;
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static Future<List<CoinPackage>> getPackages() async {
    final res = await http.get(
      Uri.parse('${AiBackendConstants.baseUrl}/api/v1/coins/packages'),
      headers: await _headers(),
    );
    if (res.statusCode != 200) {
      throw Exception('Failed to load coin packages (${res.statusCode})');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return (data['packages'] as List)
        .map((p) => CoinPackage.fromJson(p as Map<String, dynamic>))
        .toList();
  }

  static Future<PurchaseIntent> createIntent(String packageId) async {
    final res = await http.post(
      Uri.parse('${AiBackendConstants.baseUrl}/api/v1/coins/purchase/create-intent'),
      headers: await _headers(),
      body: jsonEncode({'package_id': packageId}),
    );
    if (res.statusCode != 200) {
      Map<String, dynamic>? data;
      try {
        data = jsonDecode(res.body) as Map<String, dynamic>;
      } catch (_) {}
      final detail = data?['detail'];
      throw Exception(detail is String ? detail : 'Failed to start purchase (${res.statusCode})');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return PurchaseIntent(
      clientSecret: data['client_secret'] as String,
      publishableKey: data['publishable_key'] as String,
      amountUsdCents: (data['amount_usd_cents'] as num).toInt(),
      coins: (data['coins'] as num).toInt(),
    );
  }
}
