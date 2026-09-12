import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants/supabase_constants.dart';
import '../models/conversation.dart';
import 'supabase_service.dart';

/// Direct messages, talking to the Python backend rather than Supabase
/// directly — see messaging.py for why: every read/write goes through
/// the service-role client so a conversation can never silently fail
/// to reach the other person the way likes/comments once did here.
class MessagingService {
  static Future<Map<String, String>> _headers() async {
    final token = SupabaseService.client.auth.currentSession?.accessToken;
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static String? _errorDetail(http.Response res) {
    try {
      final data = jsonDecode(res.body);
      final detail = data is Map ? data['detail'] : null;
      return detail is String ? detail : null;
    } catch (_) {
      return null;
    }
  }

  /// Starts a conversation with [otherUserId], or returns the existing
  /// one — safe to call every time "Message" is tapped rather than
  /// tracking whether a conversation already exists on the client.
  static Future<Conversation> startConversation(String otherUserId) async {
    final res = await http.post(
      Uri.parse('${AiBackendConstants.baseUrl}/api/v1/conversations'),
      headers: await _headers(),
      body: jsonEncode({'other_user_id': otherUserId}),
    );
    if (res.statusCode != 200) {
      throw Exception(_errorDetail(res) ?? 'Could not start conversation (${res.statusCode})');
    }
    return Conversation.fromJson(jsonDecode(res.body));
  }

  static Future<List<Conversation>> getConversations() async {
    final res = await http.get(
      Uri.parse('${AiBackendConstants.baseUrl}/api/v1/conversations'),
      headers: await _headers(),
    );
    if (res.statusCode != 200) {
      throw Exception(_errorDetail(res) ?? 'Could not load conversations (${res.statusCode})');
    }
    final data = jsonDecode(res.body);
    return ((data['conversations'] as List?) ?? [])
        .map((c) => Conversation.fromJson(c as Map<String, dynamic>))
        .toList();
  }

  /// [before] pages backward through history — pass the oldest message
  /// already loaded to fetch the page before it.
  static Future<List<ChatMessage>> getMessages(
    String conversationId, {
    DateTime? before,
    int limit = 50,
  }) async {
    final uri = Uri.parse(
      '${AiBackendConstants.baseUrl}/api/v1/conversations/$conversationId/messages',
    ).replace(queryParameters: {
      if (before != null) 'before': before.toUtc().toIso8601String(),
      'limit': '$limit',
    });
    final res = await http.get(uri, headers: await _headers());
    if (res.statusCode != 200) {
      throw Exception(_errorDetail(res) ?? 'Could not load messages (${res.statusCode})');
    }
    final data = jsonDecode(res.body);
    return ((data['messages'] as List?) ?? [])
        .map((m) => ChatMessage.fromJson(m as Map<String, dynamic>))
        .toList();
  }

  static Future<ChatMessage> sendMessage(String conversationId, String content) async {
    final res = await http.post(
      Uri.parse('${AiBackendConstants.baseUrl}/api/v1/conversations/$conversationId/messages'),
      headers: await _headers(),
      body: jsonEncode({'content': content}),
    );
    if (res.statusCode != 200) {
      throw Exception(_errorDetail(res) ?? 'Could not send message (${res.statusCode})');
    }
    return ChatMessage.fromJson(jsonDecode(res.body));
  }

  static Future<void> markRead(String conversationId) async {
    final res = await http.post(
      Uri.parse('${AiBackendConstants.baseUrl}/api/v1/conversations/$conversationId/read'),
      headers: await _headers(),
    );
    if (res.statusCode != 200) {
      throw Exception(_errorDetail(res) ?? 'Could not mark messages read (${res.statusCode})');
    }
  }
}
