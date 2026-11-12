import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../constants/supabase_constants.dart';
import 'bunny_stream_service.dart';
import 'supabase_service.dart';

/// Where to PUT the source video for an AI Repurposer job. The path is
/// chosen by the backend inside the private `repurpose-sources` bucket,
/// so the creator's original video is never publicly readable.
class RepurposeUploadTicket {
  final String uploadUrl;
  final String sourcePath;
  final int maxBytes;

  const RepurposeUploadTicket({required this.uploadUrl, required this.sourcePath, required this.maxBytes});
}

/// Where to upload a video too large for the storage plan's upload cap: a
/// Bunny Stream video created for this user, plus the repurposer path to
/// start the job from.
class RepurposeBunnyTicket {
  final BunnyStreamCredentials credentials;
  final String sourcePath;
  final int maxBytes;

  const RepurposeBunnyTicket({required this.credentials, required this.sourcePath, required this.maxBytes});
}

class RepurposeService {
  /// Uploads above this go to Bunny instead of Supabase Storage. A Free
  /// Supabase project refuses anything over 50 MB.
  static const supabaseUploadCapBytes = 45 * 1024 * 1024;

  static const _contentTypes = {
    'mp4': 'video/mp4',
    'mov': 'video/quicktime',
    'webm': 'video/webm',
    'mkv': 'video/x-matroska',
    '3gp': 'video/3gpp',
    'm4v': 'video/x-m4v',
  };

  static String contentTypeFor(XFile file) {
    final ext = file.name.contains('.') ? file.name.split('.').last.toLowerCase() : '';
    return _contentTypes[ext] ?? file.mimeType ?? 'video/mp4';
  }

  static Map<String, String> _authHeaders() {
    final token = SupabaseService.client.auth.currentSession?.accessToken;
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// Whether this account's next run is its free first video. Null when it
  /// can't be checked (guest, offline, older backend) — callers fall back
  /// to showing the coin price, and the backend still decides at start.
  static Future<RepurposeFreeTrial?> freeTrialStatus() async {
    if (SupabaseService.isGuest || SupabaseService.client.auth.currentSession == null) return null;
    try {
      final res = await http
          .get(Uri.parse('${AiBackendConstants.baseUrl}/api/v1/repurpose/free-trial'), headers: _authHeaders())
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return null;
      final body = jsonDecode(res.body);
      if (body is! Map) return null;
      return RepurposeFreeTrial(
        eligible: body['eligible'] == true,
        maxMinutes: (body['max_minutes'] as num?)?.toInt() ?? 10,
      );
    } catch (_) {
      return null;
    }
  }

  /// A copy of a finished clip with a small "Made with Viyo" tag, for
  /// downloading or sharing outside the app. Null if it couldn't be made.
  static Future<String?> brandedClipUrl({required String jobId, required int rank}) async {
    try {
      final res = await http
          .post(Uri.parse('${AiBackendConstants.baseUrl}/api/v1/repurpose/$jobId/clips/$rank/branded'),
              headers: _authHeaders())
          .timeout(const Duration(seconds: 120));
      if (res.statusCode != 200) return null;
      final body = jsonDecode(res.body);
      return body is Map ? body['url'] as String? : null;
    } catch (_) {
      return null;
    }
  }

  /// A version of a finished clip for one platform ("tiktok", "shorts" or "reels"): captions placed
  /// clear of that app's buttons, plus the packaging written for it. Null if it couldn't be made.
  static Future<Map<String, dynamic>?> platformClip(
      {required String jobId, required int rank, required String platform, bool tag = false, String? version}) async {
    try {
      final q = [if (tag) 'tag=true', if (version != null) 'version=$version'].join('&');
      final res = await http
          .post(
              Uri.parse('${AiBackendConstants.baseUrl}/api/v1/repurpose/$jobId/clips/$rank/platform/$platform'
                  '${q.isEmpty ? '' : '?$q'}'),
              headers: _authHeaders())
          .timeout(const Duration(seconds: 180));
      if (res.statusCode != 200) return null;
      final body = jsonDecode(res.body);
      return body is Map ? Map<String, dynamic>.from(body) : null;
    } catch (_) {
      return null;
    }
  }

  /// Makes a clip again with some of the editor's changes switched off (or back on). Returns
  /// {version, url, edits, quality}, or throws a [StateError] with a message the creator can read.
  static Future<Map<String, dynamic>> clipEdits(
      {required String jobId, required int rank, required Map<String, bool> toggles}) async {
    final res = await http
        .post(Uri.parse('${AiBackendConstants.baseUrl}/api/v1/repurpose/$jobId/clips/$rank/edits'),
            headers: {..._authHeaders(), 'Content-Type': 'application/json'}, body: jsonEncode(toggles))
        .timeout(const Duration(seconds: 240));
    final body = jsonDecode(res.body);
    if (res.statusCode != 200) {
      throw StateError(body is Map && body['detail'] is String ? body['detail'] as String : "Couldn't make this version.");
    }
    return Map<String, dynamic>.from(body as Map);
  }

  static Future<RepurposeUploadTicket> requestUpload({required String contentType, required int sizeBytes}) async {
    final res = await http.post(
      Uri.parse('${AiBackendConstants.baseUrl}/api/v1/repurpose/uploads'),
      headers: _authHeaders(),
      body: jsonEncode({'content_type': contentType, 'size_bytes': sizeBytes}),
    );
    final body = jsonDecode(res.body);
    if (res.statusCode != 200) {
      throw Exception(body is Map ? (body['detail'] ?? 'Upload could not start') : 'Upload could not start');
    }
    return RepurposeUploadTicket(
      uploadUrl: body['upload_url'] as String,
      sourcePath: body['source_path'] as String,
      maxBytes: (body['max_bytes'] as num).toInt(),
    );
  }

  static Future<RepurposeBunnyTicket> requestBunnyUpload({required int sizeBytes}) async {
    final res = await http.post(
      Uri.parse('${AiBackendConstants.baseUrl}/api/v1/repurpose/bunny-uploads'),
      headers: _authHeaders(),
      body: jsonEncode({'size_bytes': sizeBytes}),
    );
    final body = jsonDecode(res.body);
    if (res.statusCode != 200) {
      throw Exception(body is Map ? (body['detail'] ?? 'Upload could not start') : 'Upload could not start');
    }
    return RepurposeBunnyTicket(
      credentials: BunnyStreamCredentials.fromJson(body as Map<String, dynamic>),
      sourcePath: body['source_path'] as String,
      maxBytes: (body['max_bytes'] as num).toInt(),
    );
  }

  /// Uploads straight to Supabase Storage through the signed URL. On
  /// mobile the file is streamed from disk instead of read into memory
  /// first, so a several-hundred-MB video doesn't have to fit in RAM.
  static Future<void> uploadSource(
    XFile file,
    RepurposeUploadTicket ticket,
    String contentType, {
    void Function(double progress)? onProgress,
  }) async {
    final size = await file.length();
    final token = SupabaseService.client.auth.currentSession?.accessToken;
    try {
      await Dio().put(
        ticket.uploadUrl,
        data: kIsWeb ? await file.readAsBytes() : file.openRead(),
        options: Options(headers: {
          'Content-Type': contentType,
          Headers.contentLengthHeader: size,
          'apikey': SupabaseConstants.anonKey,
          if (token != null) 'Authorization': 'Bearer $token',
          'x-upsert': 'false',
        }),
        onSendProgress: (sent, total) {
          if (onProgress != null && size > 0) onProgress((sent / size).clamp(0.0, 1.0));
        },
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 413) {
        throw Exception('This video is larger than uploads currently allow. Try a shorter or smaller file.');
      }
      // Say what the storage service actually answered, instead of a generic
      // Dio error: the status, the reason it gave, and what we sent.
      final status = e.response?.statusCode;
      var reason = '';
      try {
        final data = e.response?.data;
        if (data is Map) {
          reason = (data['message'] ?? data['error'] ?? data['detail'] ?? '').toString();
        } else if (data is String) {
          reason = data;
        } else if (data is List<int>) {
          reason = utf8.decode(data, allowMalformed: true);
        }
      } catch (_) {}
      if (reason.length > 200) reason = reason.substring(0, 200);
      throw Exception(
        'Upload to storage failed${status != null ? ' ($status)' : ''}'
        '${reason.isNotEmpty ? ': $reason' : ''} '
        '[type $contentType, ${(size / (1024 * 1024)).toStringAsFixed(1)} MB]',
      );
    }
  }
}


class RepurposeFreeTrial {
  final bool eligible;
  final int maxMinutes;
  const RepurposeFreeTrial({required this.eligible, required this.maxMinutes});
}
