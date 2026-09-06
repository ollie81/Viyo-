import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants/supabase_constants.dart';
import '../models/insufficient_coins_exception.dart';
import 'supabase_service.dart';

/// Boosting spends coins, so — like every other coin-gated action in
/// this app — it goes through the Python backend's audited spend logic
/// rather than the old `boost_post` Postgres RPC, which took a
/// client-supplied cost with no way to confirm it validated that
/// amount server-side.
class PostBoostService {
  static Future<Map<String, String>> _headers() async {
    final token = SupabaseService.client.auth.currentSession?.accessToken;
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static Future<void> boostPost(String postId) async {
    final res = await http.post(
      Uri.parse('${AiBackendConstants.baseUrl}/api/v1/boost-post'),
      headers: await _headers(),
      body: jsonEncode({'post_id': postId}),
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
    throw Exception(detail is String ? detail : 'Failed to boost post (${res.statusCode})');
  }
}
