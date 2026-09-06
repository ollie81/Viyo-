import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants/supabase_constants.dart';
import '../models/insufficient_coins_exception.dart';
import 'supabase_service.dart';

/// Discover Spotlight — pay coins for temporary priority placement in
/// the suggested-creators list. "Who's currently spotlighted" has to
/// come from the backend (not a direct Supabase query): it's derived
/// from other users' transaction history, which a normal user-scoped
/// client can't read past its own rows under RLS.
class DiscoverSpotlightService {
  static Future<Map<String, String>> _headers() async {
    final token = SupabaseService.client.auth.currentSession?.accessToken;
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static Future<void> spotlightMe() async {
    final res = await http.post(
      Uri.parse('${AiBackendConstants.baseUrl}/api/v1/spotlight'),
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
    throw Exception(detail is String ? detail : 'Failed to spotlight (${res.statusCode})');
  }

  /// User IDs currently spotlighted, most-recent first. Best-effort by
  /// design at every call site — a failed lookup should degrade to an
  /// unranked suggested-creators list, never break Discover entirely.
  static Future<List<String>> getActiveSpotlightIds() async {
    final res = await http.get(
      Uri.parse('${AiBackendConstants.baseUrl}/api/v1/spotlight/active'),
      headers: await _headers(),
    );
    if (res.statusCode != 200) {
      throw Exception('Failed to load spotlights (${res.statusCode})');
    }
    final data = jsonDecode(res.body);
    return List<String>.from(data['user_ids'] ?? const []);
  }
}
