import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants/supabase_constants.dart';
import '../models/insufficient_coins_exception.dart';
import 'supabase_service.dart';

/// Series-level promotion boost — a creator spends coins to feature
/// their whole drama series in Discover/Trending for a fixed window
/// (see viyo_ai/series_boost.py). Distinct from PostBoostService, which
/// only lifts one episode's own score and never expires.
///
/// "Which series are currently boosted" has to come from the backend,
/// same reasoning as DiscoverSpotlightService: it's derived from other
/// creators' transaction history, unreadable past your own rows under
/// RLS from a direct client query.
class SeriesBoostService {
  static Future<Map<String, String>> _headers() async {
    final token = SupabaseService.client.auth.currentSession?.accessToken;
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static Future<void> boostSeries(String seriesId) async {
    final res = await http.post(
      Uri.parse('${AiBackendConstants.baseUrl}/api/v1/series/$seriesId/boost'),
      headers: await _headers(),
    );
    if (res.statusCode == 200) return;

    Map<String, dynamic>? data;
    try {
      data = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {}
    final detail = data?['detail'];
    if (res.statusCode == 402 && detail is Map) {
      throw InsufficientCoinsException(
        feature: detail['feature'] as String? ?? '',
        balance: (detail['balance'] as num?)?.toInt() ?? 0,
        needed: (detail['needed'] as num?)?.toInt() ?? 0,
      );
    }
    throw Exception(detail is String ? detail : 'Failed to boost series (${res.statusCode})');
  }

  /// Series IDs currently boosted, most-recent first. Best-effort by
  /// design at every call site — a failed lookup should degrade to
  /// unranked/unbadged trending, never break the Dramas home entirely.
  static Future<List<String>> getActiveBoostedSeriesIds() async {
    final res = await http.get(
      Uri.parse('${AiBackendConstants.baseUrl}/api/v1/series/boosted/active'),
      headers: await _headers(),
    );
    if (res.statusCode != 200) {
      throw Exception('Failed to load boosted series (${res.statusCode})');
    }
    final data = jsonDecode(res.body);
    return List<String>.from(data['series_ids'] ?? const []);
  }
}
