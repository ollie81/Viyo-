import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants/supabase_constants.dart';
import '../models/post_feedback.dart';
import 'supabase_service.dart';

/// Talks to the Python FastAPI backend (see /backend). Every request
/// includes the user's Supabase JWT so the backend can verify identity
/// and apply per-user rate limiting on OpenAI calls.
class AiService {
  static Future<Map<String, String>> _headers() async {
    final token = SupabaseService.client.auth.currentSession?.accessToken;
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static Future<List<String>> getContentIdeas(String niche) async {
    final res = await http.post(
      Uri.parse('${AiBackendConstants.baseUrl}/content-ideas'),
      headers: await _headers(),
      body: jsonEncode({'niche': niche}),
    );
    if (res.statusCode != 200) {
      throw Exception('Failed to fetch content ideas (${res.statusCode})');
    }
    final data = jsonDecode(res.body);
    return List<String>.from(data['ideas']);
  }

  static Future<String> improveCaption(String caption) async {
    final res = await http.post(
      Uri.parse('${AiBackendConstants.baseUrl}/improve-caption'),
      headers: await _headers(),
      body: jsonEncode({'caption': caption}),
    );
    if (res.statusCode != 200) {
      throw Exception('Failed to improve caption (${res.statusCode})');
    }
    final data = jsonDecode(res.body);
    return data['improved_caption'];
  }

  static Future<Map<String, dynamic>> getPostFeedback(String captionOrDescription) async {
    final res = await http.post(
      Uri.parse('${AiBackendConstants.baseUrl}/post-feedback'),
      headers: await _headers(),
      body: jsonEncode({'content': captionOrDescription}),
    );
    if (res.statusCode != 200) {
      throw Exception('Failed to get feedback (${res.statusCode})');
    }
    return jsonDecode(res.body);
  }

  /// The AI Creator Coach — called right after a post is created.
  /// Framed as coaching (what worked / what to improve / ideas / tip),
  /// not a numeric score, so it feels like mentorship, not grading.
  static Future<PostFeedback> analyzePost({
    required String postType,
    required String caption,
    String niche = '',
  }) async {
    final res = await http.post(
      Uri.parse('${AiBackendConstants.baseUrl}/analyze-post'),
      headers: await _headers(),
      body: jsonEncode({
        'post_type': postType,
        'caption': caption,
        'niche': niche,
      }),
    );
    if (res.statusCode != 200) {
      throw Exception('Failed to analyze post (${res.statusCode})');
    }
    return PostFeedback.fromAiResponse(jsonDecode(res.body));
  }
}

