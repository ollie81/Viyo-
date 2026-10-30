import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../constants/supabase_constants.dart';
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

class RepurposeService {
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
      rethrow;
    }
  }
}
