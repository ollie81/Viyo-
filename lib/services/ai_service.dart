import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants/supabase_constants.dart';
import '../models/caption_variants.dart';
import '../models/hook_feedback.dart';
import '../models/post_feedback.dart';
import '../models/trending_result.dart';
import '../models/voice_check_result.dart';
import '../models/weekly_report.dart';
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

  /// Loads the persistent AI Coach conversation for one video.
  static Future<List<Map<String, dynamic>>> getCoachHistory(
      String videoId) async {
    final res = await http.get(
      Uri.parse(
        '${AiBackendConstants.baseUrl}/api/v1/coach/${Uri.encodeComponent(videoId)}',
      ),
      headers: await _headers(),
    );

    if (res.statusCode != 200) {
      throw Exception('Failed to load Coach history (${res.statusCode})');
    }

    final data = jsonDecode(res.body);
    return List<Map<String, dynamic>>.from(data['messages'] ?? const []);
  }

  /// Sends a message to the Coach. The backend keeps the history attached
  /// to this specific video.
  static Future<Map<String, dynamic>> sendCoachMessage({
    required String videoId,
    required String message,
    int videoVersion = 1,
  }) async {
    final res = await http.post(
      Uri.parse('${AiBackendConstants.baseUrl}/api/v1/coach/message'),
      headers: await _headers(),
      body: jsonEncode({
        'video_id': videoId,
        'message': message,
        'video_version': videoVersion,
      }),
    );

    if (res.statusCode != 200) {
      String detail = 'Coach request failed (${res.statusCode})';
      try {
        final data = jsonDecode(res.body);
        detail = data['detail'] ?? detail;
      } catch (_) {}
      throw Exception(detail);
    }

    return Map<String, dynamic>.from(jsonDecode(res.body));
  }

  /// Permanently deletes the creator's account: coach history, posts,
  /// profile, and the underlying Supabase auth user. Irreversible.
  static Future<void> deleteAccount() async {
    final res = await http.delete(
      Uri.parse('${AiBackendConstants.baseUrl}/api/v1/account'),
      headers: await _headers(),
    );

    if (res.statusCode != 200) {
      String detail = 'Failed to delete account (${res.statusCode})';
      try {
        final data = jsonDecode(res.body);
        detail = data['detail'] ?? detail;
      } catch (_) {}
      throw Exception(detail);
    }
  }

  /// Fast, narrow check on just the opening — the caption's first line,
  /// or (with imageUrl) a video's first frame — not the whole post.
  /// Meant for a quick pre-post check, not the full analyzePost review.
  static Future<HookFeedback> analyzeHook({
    required String hookText,
    String niche = '',
    String? imageUrl,
  }) async {
    final res = await http.post(
      Uri.parse('${AiBackendConstants.baseUrl}/analyze-hook'),
      headers: await _headers(),
      body: jsonEncode({
        'hook_text': hookText,
        'niche': niche,
        if (imageUrl != null) 'image_url': imageUrl,
      }),
    );
    if (res.statusCode != 200) {
      String detail = 'Failed to check hook (${res.statusCode})';
      try {
        final data = jsonDecode(res.body);
        detail = data['detail'] ?? detail;
      } catch (_) {}
      throw Exception(detail);
    }
    return HookFeedback.fromAiResponse(jsonDecode(res.body));
  }

  /// The AI Creator Coach — called right after a post is created.
  /// Framed as coaching (what worked / what to improve / ideas / tip),
  /// not a numeric score, so it feels like mentorship, not grading.
  static Future<PostFeedback> analyzePost({
    required String postType,
    required String caption,
    String niche = '',
    String? imageUrl,
  }) async {
    final res = await http.post(
      Uri.parse('${AiBackendConstants.baseUrl}/analyze-post'),
      headers: await _headers(),
      body: jsonEncode({
        'post_type': postType,
        'caption': caption,
        'niche': niche,
        if (imageUrl != null) 'image_url': imageUrl,
      }),
    );
    if (res.statusCode != 200) {
      throw Exception('Failed to analyze post (${res.statusCode})');
    }
    return PostFeedback.fromAiResponse(jsonDecode(res.body));
  }

  /// Caption/title variants for a rough idea — grounded in the creator's
  /// own best-performing past captions when they have enough post
  /// history, generic otherwise (see CaptionVariants.personalized).
  static Future<CaptionVariants> getCaptionVariants({
    required String draft,
    String niche = '',
  }) async {
    final res = await http.post(
      Uri.parse('${AiBackendConstants.baseUrl}/api/v1/caption-variants'),
      headers: await _headers(),
      body: jsonEncode({'draft': draft, 'niche': niche}),
    );
    if (res.statusCode != 200) {
      String detail = 'Failed to generate captions (${res.statusCode})';
      try {
        final data = jsonDecode(res.body);
        detail = data['detail'] ?? detail;
      } catch (_) {}
      throw Exception(detail);
    }
    return CaptionVariants.fromAiResponse(jsonDecode(res.body));
  }

  /// Rolls up this week's Coach scores and post engagement into a
  /// short report card — computed stats plus a one-paragraph note in
  /// the Coach's voice.
  static Future<WeeklyReport> getWeeklyReport() async {
    final res = await http.get(
      Uri.parse('${AiBackendConstants.baseUrl}/api/v1/weekly-report'),
      headers: await _headers(),
    );
    if (res.statusCode != 200) {
      String detail = 'Failed to load weekly report (${res.statusCode})';
      try {
        final data = jsonDecode(res.body);
        detail = data['detail'] ?? detail;
      } catch (_) {}
      throw Exception(detail);
    }
    return WeeklyReport.fromJson(jsonDecode(res.body));
  }

  /// Checks whether a draft caption sounds consistent with this
  /// creator's established voice (learned from their own past
  /// captions), or reads off-brand. hasVoiceProfile is false when
  /// there isn't enough post history yet for this to mean anything.
  static Future<VoiceCheckResult> checkVoice(String draft) async {
    final res = await http.post(
      Uri.parse('${AiBackendConstants.baseUrl}/api/v1/voice-check'),
      headers: await _headers(),
      body: jsonEncode({'draft': draft}),
    );
    if (res.statusCode != 200) {
      String detail = 'Failed to check voice (${res.statusCode})';
      try {
        final data = jsonDecode(res.body);
        detail = data['detail'] ?? detail;
      } catch (_) {}
      throw Exception(detail);
    }
    return VoiceCheckResult.fromJson(jsonDecode(res.body));
  }

  /// What's actually getting engagement right now among other creators
  /// in this niche, on this app — the only "trending" signal available
  /// without a TikTok/Instagram/YouTube integration.
  static Future<TrendingResult> getTrending(String niche) async {
    final uri = Uri.parse('${AiBackendConstants.baseUrl}/api/v1/trending')
        .replace(queryParameters: {'niche': niche});
    final res = await http.get(uri, headers: await _headers());
    if (res.statusCode != 200) {
      String detail = 'Failed to load trends (${res.statusCode})';
      try {
        final data = jsonDecode(res.body);
        detail = data['detail'] ?? detail;
      } catch (_) {}
      throw Exception(detail);
    }
    return TrendingResult.fromJson(jsonDecode(res.body));
  }
}


