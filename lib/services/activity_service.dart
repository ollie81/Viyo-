import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../constants/supabase_constants.dart';

/// Sends what the viewer does (seen in the feed, how far they watched, finished, not interested, searches) to the
/// backend, which checks every event and uses it for For You, trending and creators' analytics. Batched and
/// best-effort: a lost event never interrupts watching. Likes, comments, shares and views are recorded by the
/// server itself when they happen.
class ActivityService {
  static final List<Map<String, dynamic>> _queue = [];
  static Timer? _timer;
  static final Set<String> _seenThisSession = {};

  static void _add(Map<String, dynamic> e) {
    if (Supabase.instance.client.auth.currentSession == null) return;
    _queue.add(e);
    if (_queue.length >= 20) {
      flush();
    } else {
      _timer ??= Timer(const Duration(seconds: 8), flush);
    }
  }

  /// A post shown on screen (once per app session).
  static void impression(String postId) {
    if (_seenThisSession.add(postId)) _add({'kind': 'impression', 'post_id': postId});
  }

  /// How far the viewer got (0..1) when they left a video; 90% or more counts as finished.
  static void progress(String postId, double fraction) {
    if (fraction <= 0.02) return;
    _add({'kind': 'progress', 'post_id': postId, 'value': fraction.clamp(0.0, 1.0)});
  }

  static void complete(String postId) => _add({'kind': 'complete', 'post_id': postId});
  static void notInterested(String postId) => _add({'kind': 'not_interested', 'post_id': postId});
  static void notInterestedCreator(String creatorId) =>
      _add({'kind': 'not_interested_creator', 'creator_id': creatorId});

  static Future<void> flush() async {
    _timer?.cancel();
    _timer = null;
    if (_queue.isEmpty) return;
    final batch = List<Map<String, dynamic>>.from(_queue.take(50));
    _queue.removeRange(0, batch.length);
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    try {
      await http.post(Uri.parse('${AiBackendConstants.baseUrl}/api/v1/events'),
          headers: {'Content-Type': 'application/json', if (token != null) 'Authorization': 'Bearer $token'},
          body: jsonEncode({'events': batch}));
    } catch (_) {}
    if (_queue.isNotEmpty) _timer ??= Timer(const Duration(seconds: 2), flush);
  }

  // --- Viewer choices -------------------------------------------------------

  static Map<String, String> get _headers {
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    return {'Content-Type': 'application/json', if (token != null) 'Authorization': 'Bearer $token'};
  }

  static Future<bool> personalized() async {
    final res = await http.get(Uri.parse('${AiBackendConstants.baseUrl}/api/v1/viewer/prefs'), headers: _headers);
    if (res.statusCode != 200) return true;
    return (jsonDecode(res.body) as Map)['personalized'] != false;
  }

  static Future<void> setPersonalized(bool on) async {
    final res = await http.put(Uri.parse('${AiBackendConstants.baseUrl}/api/v1/viewer/prefs'),
        headers: _headers, body: jsonEncode({'personalized': on}));
    if (res.statusCode != 200) throw Exception('Could not save (${res.statusCode})');
  }

  static Future<void> clearHistory() async {
    final res = await http.delete(Uri.parse('${AiBackendConstants.baseUrl}/api/v1/viewer/history'), headers: _headers);
    if (res.statusCode != 200) throw Exception('Could not clear your history (${res.statusCode})');
  }
}
