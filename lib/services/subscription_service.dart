import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants/supabase_constants.dart';
import 'supabase_service.dart';

/// Viyo Premium status (GET /api/v1/subscription/status). Premium is sold through NardoPay subscriptions
/// (PremiumCheckoutApi below); members who subscribed earlier through Lemon Squeezy show provider 'lemonsqueezy'.
class SubscriptionStatus {
  final bool isSubscribed;
  final String? plan;
  final String? provider; // nardopay | lemonsqueezy (earlier subscriptions)
  final String? status;
  final String? renewsAt;
  final String? endsAt;

  SubscriptionStatus({
    required this.isSubscribed,
    this.plan,
    this.provider,
    this.status,
    this.renewsAt,
    this.endsAt,
  });

  factory SubscriptionStatus.fromJson(Map<String, dynamic> json) => SubscriptionStatus(
        isSubscribed: json['is_subscribed'] ?? false,
        plan: json['plan'] as String?,
        provider: json['provider'] as String?,
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

/// One NardoPay Premium subscription checkout, as the server reports it. 'active' only after NardoPay's signed
/// payment webhook was verified on the server; the redirect back to VIYO never activates anything.
class PremiumSubscription {
  final String id;
  final String status; // pending | active | lapsed | failed
  final String plan;
  final String? paymentLink;

  const PremiumSubscription({required this.id, required this.status, required this.plan, this.paymentLink});

  factory PremiumSubscription.fromJson(Map<String, dynamic> j) => PremiumSubscription(
        id: '${j['subscription_id']}',
        status: '${j['status']}',
        plan: '${j['plan']}',
        paymentLink: j['payment_link'] as String?,
      );
}

/// The server calls for a NardoPay Premium subscription (a fake in tests).
class PremiumCheckoutApi {
  const PremiumCheckoutApi();

  static Future<Map<String, String>> _headers() async {
    final token = SupabaseService.client.auth.currentSession?.accessToken;
    return {'Content-Type': 'application/json', if (token != null) 'Authorization': 'Bearer $token'};
  }

  static String get _base => '${AiBackendConstants.baseUrl}/api/v1/subscription/nardopay';

  static String _error(http.Response res) {
    try {
      final d = jsonDecode(res.body)['detail'];
      if (d is String) return d;
    } catch (_) {}
    return 'Premium checkout failed (${res.statusCode}).';
  }

  /// Creates this user's NardoPay subscription link for [plan]; the price and billing cycle are set on the server.
  Future<PremiumSubscription> create(String plan) async {
    final res = await http.post(Uri.parse('$_base/create'), headers: await _headers(), body: jsonEncode({'plan': plan}));
    if (res.statusCode != 200) throw Exception(_error(res));
    return PremiumSubscription.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<PremiumSubscription> status(String id) async {
    final res = await http.get(Uri.parse('$_base/$id'), headers: await _headers());
    if (res.statusCode != 200) throw Exception(_error(res));
    return PremiumSubscription.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }
}
