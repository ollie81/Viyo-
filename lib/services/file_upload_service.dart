import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import '../constants/supabase_constants.dart';
import 'supabase_service.dart';

/// Where photos are uploaded. Supabase (the default): straight to Storage with
/// the user's own session, as before. Bunny: through the server, because
/// Bunny's key must never be in the app. The server says which, so the app
/// follows the switch without an update.
class FileUploadService {
  static String? _store;
  static DateTime? _checkedAt;

  /// Overridable in tests.
  static Future<String> Function() fetchStore = _fetchStore;

  static Future<String> _fetchStore() async {
    final res = await http
        .get(Uri.parse('${AiBackendConstants.baseUrl}/api/v1/files/config'))
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) return 'supabase';
    final body = jsonDecode(res.body);
    return body is Map && body['store'] == 'bunny' ? 'bunny' : 'supabase';
  }

  /// True when files go through the server to Bunny. Checked at most every 10 minutes; any error means
  /// Supabase, the way it always worked.
  static Future<bool> usesServer() async {
    final now = DateTime.now();
    if (_store == null || _checkedAt == null || now.difference(_checkedAt!) > const Duration(minutes: 10)) {
      try {
        _store = await fetchStore();
      } catch (_) {
        _store ??= 'supabase';
      }
      _checkedAt = now;
    }
    return _store == 'bunny';
  }

  static void resetForTests() {
    _store = null;
    _checkedAt = null;
  }

  static Map<String, String> _auth() {
    final token = SupabaseService.client.auth.currentSession?.accessToken;
    return {if (token != null) 'Authorization': 'Bearer $token'};
  }

  /// Uploads through the server. [kind] is "post_media" or "avatar". Returns the file's public URL.
  static Future<String> upload(
    List<int> bytes, {
    required String kind,
    required String fileName,
    required String contentType,
    void Function(double progress)? onProgress,
  }) async {
    final form = FormData.fromMap({
      'kind': kind,
      'file': MultipartFile.fromBytes(bytes, filename: fileName, contentType: DioMediaType.parse(contentType)),
    });
    try {
      final res = await Dio().post(
        '${AiBackendConstants.baseUrl}/api/v1/files/upload',
        data: form,
        options: Options(headers: _auth()),
        onSendProgress: (sent, total) {
          if (total > 0) onProgress?.call(sent / total);
        },
      );
      return (res.data as Map)['url'] as String;
    } on DioException catch (e) {
      final data = e.response?.data;
      throw Exception(data is Map && data['detail'] is String ? data['detail'] : 'Upload failed. Try again.');
    }
  }

  /// Removes the user's own post files by URL (the server skips anything that isn't theirs).
  static Future<void> delete(List<String> urls) async {
    if (urls.isEmpty) return;
    await http
        .post(Uri.parse('${AiBackendConstants.baseUrl}/api/v1/files/delete'),
            headers: {..._auth(), 'Content-Type': 'application/json'}, body: jsonEncode({'urls': urls}))
        .timeout(const Duration(seconds: 20));
  }
}
