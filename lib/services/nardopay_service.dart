import 'dart:convert';

import 'package:http/http.dart' as http;

import '../constants/supabase_constants.dart';
import 'supabase_service.dart';

/// A web coin order paid through NardoPay. The server creates it, sets its price and coins, and credits the coins
/// only after NardoPay's signed confirmation; this app never marks it paid.
class NardopayOrder {
  final String orderId;
  final String status;
  final int coins;
  final int bonusCoins;
  final int rwfAmount;
  final int usdCents;
  final String? paymentLink;

  const NardopayOrder(
      {required this.orderId,
      required this.status,
      required this.coins,
      this.bonusCoins = 0,
      required this.rwfAmount,
      this.usdCents = 0,
      this.paymentLink});

  /// The price the buyer sees, in US dollars (e.g. "$0.99").
  String get usdLabel => '\$${(usdCents / 100).toStringAsFixed(2)}';

  factory NardopayOrder.fromJson(Map<String, dynamic> j) => NardopayOrder(
        orderId: '${j['order_id']}',
        status: '${j['status']}',
        coins: (j['coins'] as num).toInt(),
        bonusCoins: (j['bonus_coins'] as num?)?.toInt() ?? 0,
        rwfAmount: (j['rwf_amount'] as num).toInt(),
        usdCents: (j['usd_cents'] as num?)?.toInt() ?? 0,
        paymentLink: j['payment_link'] as String?,
      );

  /// Statuses that won't change any more.
  bool get settled => const {'credited', 'failed', 'mismatch'}.contains(status);
}

/// The server calls (a fake in tests).
class NardopayApi {
  const NardopayApi();

  static Future<Map<String, String>> _headers() async {
    final token = SupabaseService.client.auth.currentSession?.accessToken;
    return {'Content-Type': 'application/json', if (token != null) 'Authorization': 'Bearer $token'};
  }

  static String get _base => '${AiBackendConstants.baseUrl}/api/v1/coins/purchase/nardopay';

  static String _error(http.Response res) {
    try {
      final d = jsonDecode(res.body)['detail'];
      if (d is String) return d;
    } catch (_) {}
    return 'NardoPay checkout failed (${res.statusCode}).';
  }

  /// Whether the server offers NardoPay checkout right now (a plain yes/no).
  Future<bool> available() async {
    try {
      final res = await http.get(Uri.parse('$_base/availability')).timeout(const Duration(seconds: 10));
      return res.statusCode == 200 && jsonDecode(res.body)['available'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Creates the order on the server (only the package is sent) and returns it with its payment link.
  Future<NardopayOrder> create(String packageId) async {
    final res = await http.post(Uri.parse('$_base/create'),
        headers: await _headers(), body: jsonEncode({'package_id': packageId}));
    if (res.statusCode != 200) throw Exception(_error(res));
    return NardopayOrder.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<NardopayOrder> status(String orderId) async {
    final res = await http.get(Uri.parse('$_base/orders/$orderId'), headers: await _headers());
    if (res.statusCode != 200) throw Exception(_error(res));
    return NardopayOrder.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }
}

/// Checks an order every [every] until it is credited, failed or mismatched, or [maxTries] checks have passed (then
/// the last status, usually 'pending', is returned). A failed check is retried, never treated as paid.
Future<String> waitForNardopayOrder(NardopayApi api, String orderId,
    {Duration every = const Duration(seconds: 4), int maxTries = 225, bool Function()? cancelled}) async {
  var last = 'pending';
  for (var i = 0; i < maxTries; i++) {
    if (cancelled?.call() ?? false) return last;
    await Future.delayed(every);
    try {
      final o = await api.status(orderId);
      last = o.status;
      if (o.settled) return last;
    } catch (_) {
      // A network blip: try again on the next check.
    }
  }
  return last;
}
