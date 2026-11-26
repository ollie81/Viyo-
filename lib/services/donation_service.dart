import 'dart:convert';

import 'package:http/http.dart' as http;

import '../constants/supabase_constants.dart';
import 'supabase_service.dart';

/// One fan donation as the server reports it. 'paid' only after NardoPay's signed payment webhook was verified on the
/// server; the redirect back to VIYO never marks anything paid.
class Donation {
  final String id;
  final String status; // pending | paid | failed | expired
  final String creatorId;
  final String? paymentLink;

  const Donation({required this.id, required this.status, required this.creatorId, this.paymentLink});

  factory Donation.fromJson(Map<String, dynamic> j) => Donation(
        id: '${j['donation_id']}',
        status: '${j['status']}',
        creatorId: '${j['creator_id']}',
        paymentLink: j['payment_link'] as String?,
      );
}

class ReceivedDonation {
  final String from;
  final String message;
  final double shareUsd;
  final String? paidAt;

  const ReceivedDonation({required this.from, required this.message, required this.shareUsd, this.paidAt});

  factory ReceivedDonation.fromJson(Map<String, dynamic> j) => ReceivedDonation(
        from: '${j['from'] ?? 'Someone'}',
        message: '${j['message'] ?? ''}',
        shareUsd: (j['share_usd'] as num?)?.toDouble() ?? 0,
        paidAt: j['paid_at'] as String?,
      );
}

/// What the donor can choose: US-dollar amounts (VIYO converts them to francs) and NardoPay's customer fee.
class DonationOptions {
  final bool available;
  final List<int> presetsCents;
  final int minCents;
  final int maxCents;
  final double? feePercent;

  const DonationOptions({
    required this.available,
    this.presetsCents = const [100, 300, 500, 1000, 2000],
    this.minCents = 100,
    this.maxCents = 50000,
    this.feePercent,
  });

  factory DonationOptions.fromJson(Map<String, dynamic> j) => DonationOptions(
        available: j['available'] == true,
        presetsCents: [for (final c in (j['presets_cents'] as List? ?? const [100, 300, 500, 1000, 2000])) (c as num).toInt()],
        minCents: (j['min_cents'] as num?)?.toInt() ?? 100,
        maxCents: (j['max_cents'] as num?)?.toInt() ?? 50000,
        feePercent: (j['fee_percent'] as num?)?.toDouble(),
      );
}

/// The server calls for fan donations (real money through NardoPay, never coins). A fake in tests.
class DonationApi {
  const DonationApi();

  static Future<Map<String, String>> _headers() async {
    final token = SupabaseService.client.auth.currentSession?.accessToken;
    return {'Content-Type': 'application/json', if (token != null) 'Authorization': 'Bearer $token'};
  }

  static String get _base => '${AiBackendConstants.baseUrl}/api/v1';

  static String _error(http.Response res) {
    try {
      final d = jsonDecode(res.body)['detail'];
      if (d is String) return d;
    } catch (_) {}
    return 'The donation couldn\'t be started (${res.statusCode}).';
  }

  /// Whether donations are open (a yes/no from the server).
  Future<bool> available() async => (await options()).available;

  Future<DonationOptions> options() async {
    try {
      final res = await http.get(Uri.parse('$_base/donations/availability')).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return const DonationOptions(available: false);
      return DonationOptions.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
    } catch (_) {
      return const DonationOptions(available: false);
    }
  }

  /// Starts a donation of [usdCents] to [creatorId]; VIYO converts it to francs for NardoPay.
  Future<Donation> start(String creatorId, String message, int usdCents) async {
    final res = await http.post(Uri.parse('$_base/creators/$creatorId/donate'),
        headers: await _headers(), body: jsonEncode({'message': message, 'usd_cents': usdCents}));
    if (res.statusCode != 200) throw Exception(_error(res));
    return Donation.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<Donation> status(String donationId) async {
    final res = await http.get(Uri.parse('$_base/donations/$donationId'), headers: await _headers());
    if (res.statusCode != 200) throw Exception(_error(res));
    return Donation.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// Donations the signed-in creator has received (paid only).
  Future<List<ReceivedDonation>> received() async {
    final res = await http.get(Uri.parse('$_base/creator/donations'), headers: await _headers());
    if (res.statusCode != 200) throw Exception(_error(res));
    final list = (jsonDecode(res.body) as Map<String, dynamic>)['donations'] as List? ?? const [];
    return [for (final d in list) ReceivedDonation.fromJson((d as Map).cast<String, dynamic>())];
  }
}
