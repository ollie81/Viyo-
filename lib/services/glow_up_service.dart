import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../constants/supabase_constants.dart';
import '../models/insufficient_coins_exception.dart';
import 'supabase_service.dart';

/// Viyo Glow Up (Stage 1): style suggestions from a selfie.
///
/// The selfie goes to the backend only for the length of one request and
/// is never stored; only the text suggestions are saved, and only when the
/// user chooses to. 18+ only.
class GlowUpService {
  static const costCoins = 10;

  static const styleGoals = {
    'everyday': 'Everyday',
    'professional': 'Professional',
    'bold': 'Bold',
    'minimal': 'Minimal',
    'event': 'Special event',
  };

  static const presentations = {
    'any': 'No preference',
    'feminine': 'Feminine',
    'masculine': 'Masculine',
    'neutral': 'Neutral',
  };

  static Map<String, String> _headers() {
    final token = SupabaseService.client.auth.currentSession?.accessToken;
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static String _detail(http.Response res, String fallback) {
    try {
      final body = jsonDecode(res.body);
      final d = body is Map ? body['detail'] : null;
      if (d is String && d.isNotEmpty) return d;
    } catch (_) {}
    return '$fallback (${res.statusCode})';
  }

  /// Returns {result, saved, session_id, coins_charged}.
  static Future<Map<String, dynamic>> analyze({
    required Uint8List imageBytes,
    required bool ageConfirmed,
    String? styleGoal,
    String? presentation,
    bool save = true,
  }) async {
    final res = await http.post(
      Uri.parse('${AiBackendConstants.baseUrl}/api/v1/glow-up/analyze'),
      headers: _headers(),
      body: jsonEncode({
        'image_base64': base64Encode(imageBytes),
        'age_confirmed': ageConfirmed,
        if (styleGoal != null) 'style_goal': styleGoal,
        if (presentation != null) 'presentation': presentation,
        'save': save,
      }),
    );
    if (res.statusCode == 402) {
      final detail = (jsonDecode(res.body) as Map)['detail'];
      if (detail is Map) {
        throw InsufficientCoinsException(
          feature: detail['feature'] as String? ?? 'glow_up_analysis',
          balance: (detail['balance'] as num?)?.toInt() ?? 0,
          needed: (detail['needed'] as num?)?.toInt() ?? costCoins,
        );
      }
    }
    if (res.statusCode != 200) {
      throw Exception(_detail(res, 'Glow Up could not finish'));
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<List<Map<String, dynamic>>> sessions() async {
    final res = await http.get(
      Uri.parse('${AiBackendConstants.baseUrl}/api/v1/glow-up/sessions'),
      headers: _headers(),
    );
    if (res.statusCode != 200) throw Exception(_detail(res, 'Could not load your Glow Ups'));
    final list = (jsonDecode(res.body) as Map)['sessions'] as List<dynamic>? ?? const [];
    return list.cast<Map<String, dynamic>>();
  }

  static Future<void> deleteSession(String id) async {
    final res = await http.delete(
      Uri.parse('${AiBackendConstants.baseUrl}/api/v1/glow-up/sessions/$id'),
      headers: _headers(),
    );
    if (res.statusCode != 200) throw Exception(_detail(res, 'Could not delete'));
  }

  static Future<void> deleteAll() async {
    final res = await http.delete(
      Uri.parse('${AiBackendConstants.baseUrl}/api/v1/glow-up/sessions'),
      headers: _headers(),
    );
    if (res.statusCode != 200) throw Exception(_detail(res, 'Could not delete'));
  }
}
