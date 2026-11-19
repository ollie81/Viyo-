import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../constants/supabase_constants.dart';

class PromotionQuote {
  final int budgetCoins, days, coinsPer1000, maxImpressions;
  final double perDayCoins;
  final List<String> terms;
  final bool enabled;
  PromotionQuote({required this.budgetCoins, required this.days, required this.coinsPer1000,
      required this.maxImpressions, required this.perDayCoins, required this.terms, required this.enabled});
  factory PromotionQuote.fromJson(Map<String, dynamic> j) => PromotionQuote(
        budgetCoins: (j['budget_coins'] as num).toInt(),
        days: (j['days'] as num).toInt(),
        coinsPer1000: (j['coins_per_1000_impressions'] as num).toInt(),
        maxImpressions: (j['max_impressions'] as num).toInt(),
        perDayCoins: (j['per_day_coins'] as num).toDouble(),
        terms: ((j['terms'] as List?) ?? []).map((e) => e.toString()).toList(),
        enabled: j['enabled'] == true,
      );
}

class AdPromotion {
  final String id;
  final String postId;
  final String status; // active | ended
  final String? endedReason;
  final int budgetCoins, coinsSpent, impressions, clicks;
  final int? coinsRefunded;
  final String caption;
  final String? thumbnailUrl;
  final DateTime? endAt;
  AdPromotion({required this.id, required this.postId, required this.status, this.endedReason,
      required this.budgetCoins, required this.coinsSpent, required this.impressions, required this.clicks,
      this.coinsRefunded, this.caption = '', this.thumbnailUrl, this.endAt});
  bool get active => status == 'active';
  factory AdPromotion.fromJson(Map<String, dynamic> j) => AdPromotion(
        id: j['id'] as String,
        postId: (j['post_id'] ?? '').toString(),
        status: (j['status'] ?? 'ended').toString(),
        endedReason: j['ended_reason'] as String?,
        budgetCoins: (j['budget_coins'] as num?)?.toInt() ?? 0,
        coinsSpent: (j['coins_spent'] as num?)?.toInt() ?? 0,
        impressions: (j['impressions'] as num?)?.toInt() ?? 0,
        clicks: (j['clicks'] as num?)?.toInt() ?? 0,
        coinsRefunded: (j['coins_refunded'] as num?)?.toInt(),
        caption: (j['caption'] ?? '').toString(),
        thumbnailUrl: j['thumbnail_url'] as String?,
        endAt: DateTime.tryParse((j['end_at'] ?? '').toString()),
      );
}

/// Paid promotion of the creator's own published ads (VIYO Coins), and the promoted ads Discover shows.
class PromotionService {
  static const _base = '${AiBackendConstants.baseUrl}/api/v1';
  static final Set<String> _counted = {}; // one impression call per promotion per app session

  static Map<String, String> get _headers {
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    return {'Content-Type': 'application/json', if (token != null) 'Authorization': 'Bearer $token'};
  }

  static Exception _failure(http.Response res, String action) {
    try {
      final d = jsonDecode(res.body)['detail'];
      if (d is String) return Exception(d);
      if (d is Map && d['error'] == 'insufficient_coins') return Exception('Not enough coins for this budget.');
    } catch (_) {}
    return Exception('Could not $action (${res.statusCode})');
  }

  static Future<PromotionQuote> quote(int budget, int days) async {
    final res = await http.get(Uri.parse('$_base/ads-maker/promotions/quote?budget=$budget&days=$days'), headers: _headers);
    if (res.statusCode != 200) throw _failure(res, 'get the price');
    return PromotionQuote.fromJson(jsonDecode(res.body));
  }

  static Future<AdPromotion> start(String postId, int budget, int days, List<String> placements) async {
    final res = await http.post(Uri.parse('$_base/ads-maker/promotions'),
        headers: _headers,
        body: jsonEncode({'post_id': postId, 'budget_coins': budget, 'days': days, 'placements': placements}));
    if (res.statusCode != 200) throw _failure(res, 'start the promotion');
    return AdPromotion.fromJson(jsonDecode(res.body));
  }

  static Future<({bool enabled, List<AdPromotion> promotions, String note})> mine() async {
    final res = await http.get(Uri.parse('$_base/ads-maker/promotions'), headers: _headers);
    if (res.statusCode != 200) throw _failure(res, 'load your promotions');
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    return (
      enabled: j['enabled'] == true,
      promotions: [for (final p in (j['promotions'] as List? ?? const [])) AdPromotion.fromJson(Map<String, dynamic>.from(p as Map))],
      note: (j['note'] ?? '').toString(),
    );
  }

  static Future<AdPromotion> stop(String id) async {
    final res = await http.post(Uri.parse('$_base/ads-maker/promotions/$id/stop'), headers: _headers);
    if (res.statusCode != 200) throw _failure(res, 'stop the promotion');
    return AdPromotion.fromJson(jsonDecode(res.body));
  }

  /// Promoted ads for a Discover placement ('for_you' or 'ads'): [(promotionId, postId)]. Empty on any error.
  static Future<List<({String promotionId, String postId})>> serve(String placement, {int limit = 2}) async {
    try {
      final res = await http.get(Uri.parse('$_base/promotions/serve?placement=$placement&limit=$limit'), headers: _headers);
      if (res.statusCode != 200) return [];
      return [
        for (final p in ((jsonDecode(res.body) as Map)['promotions'] as List? ?? const []))
          (promotionId: (p as Map)['promotion_id'].toString(), postId: p['post_id'].toString()),
      ];
    } catch (_) {
      return [];
    }
  }

  /// Counts that a promoted ad was shown (the server counts once per person per day).
  static void recordImpression(String promotionId) {
    if (!_counted.add(promotionId)) return;
    http.post(Uri.parse('$_base/promotions/$promotionId/impression'), headers: _headers).catchError((_) => http.Response('', 0));
  }

  static void recordClick(String promotionId) {
    http.post(Uri.parse('$_base/promotions/$promotionId/click'), headers: _headers).catchError((_) => http.Response('', 0));
  }
}
