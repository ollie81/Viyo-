import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants/supabase_constants.dart';
import '../models/leaderboard_entry.dart';
import 'supabase_service.dart';

/// Talks to the same FastAPI backend as AiService, but this isn't an AI
/// call — it's a plain aggregate read across every user's coin earnings,
/// which needs the backend's service-role client to see past what a
/// normal user-scoped Supabase client's RLS would allow.
class LeaderboardService {
  static Future<Map<String, String>> _headers() async {
    final token = SupabaseService.client.auth.currentSession?.accessToken;
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static Future<WeeklyLeaderboard> getWeeklyLeaderboard() async {
    final res = await http.get(
      Uri.parse('${AiBackendConstants.baseUrl}/api/v1/leaderboard/weekly'),
      headers: await _headers(),
    );
    if (res.statusCode != 200) {
      throw Exception('Failed to load leaderboard (${res.statusCode})');
    }
    return WeeklyLeaderboard.fromJson(jsonDecode(res.body));
  }
}
