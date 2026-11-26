import 'dart:convert';

import 'package:http/http.dart' as http;

import '../constants/supabase_constants.dart';
import 'supabase_service.dart';

/// One closed month of ad revenue for a creator: the ads counted on their content and what they were paid.
class AdRevenueMonth {
  final String month; // 2026-11
  final int feedAds, unlockAds;
  final double usd;
  const AdRevenueMonth({required this.month, this.feedAds = 0, this.unlockAds = 0, this.usd = 0});
  factory AdRevenueMonth.fromJson(Map j) => AdRevenueMonth(
        month: '${j['month'] ?? ''}',
        feedAds: (j['feed_ads'] as num?)?.toInt() ?? 0,
        unlockAds: (j['unlock_ads'] as num?)?.toInt() ?? 0,
        usd: (j['usd'] as num?)?.toDouble() ?? 0,
      );
}

/// Ad revenue for the signed-in creator: this month's ad count so far (dollars come when the month is closed from
/// VIYO's real AdMob totals) and the closed months.
class AdRevenueSummary {
  final bool available;
  final double creatorShare;
  final AdRevenueMonth thisMonth;
  final List<AdRevenueMonth> months;
  final String note;
  const AdRevenueSummary({required this.available, this.creatorShare = 0.5,
      this.thisMonth = const AdRevenueMonth(month: ''), this.months = const [], this.note = ''});
  factory AdRevenueSummary.fromJson(Map j) => AdRevenueSummary(
        available: j['available'] == true,
        creatorShare: (j['creator_share'] as num?)?.toDouble() ?? 0.5,
        thisMonth: j['this_month'] is Map ? AdRevenueMonth.fromJson(j['this_month'] as Map) : const AdRevenueMonth(month: ''),
        months: [for (final m in (j['months'] as List? ?? const [])) AdRevenueMonth.fromJson(m as Map)],
        note: '${j['note'] ?? ''}',
      );
}

class AdRevenueService {
  static Future<Map<String, String>> _headers() async {
    final token = SupabaseService.client.auth.currentSession?.accessToken;
    return {'Content-Type': 'application/json', if (token != null) 'Authorization': 'Bearer $token'};
  }

  static String get _base => '${AiBackendConstants.baseUrl}/api/v1';

  /// Tells the server an in-feed ad was just shown next to [postId], so its creator gets their share of the ad money.
  /// Fire-and-forget: never blocks or breaks playback.
  static Future<void> reportImpression(String postId) async {
    try {
      await http
          .post(Uri.parse('$_base/ads/impression'), headers: await _headers(), body: jsonEncode({'post_id': postId}))
          .timeout(const Duration(seconds: 10));
    } catch (_) {}
  }

  static Future<AdRevenueSummary> mine() async {
    try {
      final res = await http.get(Uri.parse('$_base/creator/ad-revenue'), headers: await _headers())
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return const AdRevenueSummary(available: false);
      return AdRevenueSummary.fromJson(jsonDecode(res.body) as Map);
    } catch (_) {
      return const AdRevenueSummary(available: false);
    }
  }

  // ---- admin (X-Admin-Key, typed in by the admin, kept in memory only)

  static Map<String, String> _admin(String key) => {'Content-Type': 'application/json', 'X-Admin-Key': key};

  static Map _ok(http.Response res) {
    final body = res.body.isEmpty ? null : jsonDecode(res.body);
    if (res.statusCode != 200) {
      final d = body is Map ? body['detail'] : null;
      throw Exception(d is String ? d : 'Failed (${res.statusCode}).');
    }
    return body as Map;
  }

  static Future<Map> adminMonth(String key, String month) async => _ok(await http
      .get(Uri.parse('$_base/admin/ad-revenue/$month'), headers: _admin(key))
      .timeout(const Duration(seconds: 20)));

  static Future<Map> adminClose(String key, String month, double feedUsd, double unlockUsd, String note) async =>
      _ok(await http
          .post(Uri.parse('$_base/admin/ad-revenue/$month/close'),
              headers: _admin(key), body: jsonEncode({'feed_usd': feedUsd, 'unlock_usd': unlockUsd, 'note': note}))
          .timeout(const Duration(seconds: 60)));
}
