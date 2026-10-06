import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants/supabase_constants.dart';
import 'supabase_service.dart';

/// Viyo Premium — a real, recurring subscription (weekly or monthly)
/// via Lemon Squeezy, mirroring CoinPurchaseService's hosted-checkout
/// pattern for Paystack/Flutterwave/Lemon Squeezy coin purchases:
/// this backend hands back a checkout URL, the caller opens it
/// externally, and there's no direct callback — the subscribe screen
/// polls getStatus() on app resume the same way BuyCoinsScreen polls
/// the coin balance.
class SubscriptionStatus {
  final bool isSubscribed;
  final String? plan;
  final String? status;
  final String? renewsAt;
  final String? endsAt;

  SubscriptionStatus({
    required this.isSubscribed,
    this.plan,
    this.status,
    this.renewsAt,
    this.endsAt,
  });

  factory SubscriptionStatus.fromJson(Map<String, dynamic> json) => SubscriptionStatus(
        isSubscribed: json['is_subscribed'] ?? false,
        plan: json['plan'] as String?,
        status: json['status'] as String?,
        renewsAt: json['renews_at'] as String?,
        endsAt: json['ends_at'] as String?,
      );
}

class SubscriptionService {
  static Future<Map<String, String>> _headers() async {
    final token = SupabaseService.client.auth.currentSession?.accessToken;
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static String? _errorDetail(http.Response res) {
    try {
      final data = jsonDecode(res.body);
      final detail = data is Map ? data['detail'] : null;
      return detail is String ? detail : null;
    } catch (_) {
      return null;
    }
  }

  /// [plan] is 'weekly' or 'monthly'. Returns the Lemon Squeezy hosted
  /// checkout URL to open externally.
  static Future<String> createCheckout(String plan) async {
    final res = await http.post(
      Uri.parse('${AiBackendConstants.baseUrl}/api/v1/subscription/checkout'),
      headers: await _headers(),
      body: jsonEncode({'plan': plan}),
    );
    if (res.statusCode != 200) {
      throw Exception(_errorDetail(res) ?? 'Could not start checkout (${res.statusCode})');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return data['checkout_url'] as String;
  }

  static Future<SubscriptionStatus> getStatus() async {
    final res = await http.get(
      Uri.parse('${AiBackendConstants.baseUrl}/api/v1/subscription/status'),
      headers: await _headers(),
    );
    if (res.statusCode != 200) {
      throw Exception(_errorDetail(res) ?? 'Could not check subscription status (${res.statusCode})');
    }
    return SubscriptionStatus.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }
}
