import 'dart:convert';
import 'package:cross_file/cross_file.dart';
import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;
import '../constants/supabase_constants.dart';
import 'supabase_service.dart';

/// Bunny Stream video upload — the video's actual bytes go straight from
/// this device to Bunny over TUS (never through our own backend, see
/// bunny_stream.py on the backend); the backend only ever hands back a
/// short-lived, single-video upload credential, never the real Bunny
/// API key.
///
/// Deliberately does NOT use the tus_client_dart package: its upload
/// loop calls dart:io's `File(file.path).existsSync()`, which compiles
/// for Flutter Web but throws UnsupportedError the moment it actually
/// runs there (dart:io is a non-functional stub on web), and this app
/// ships as a Flutter Web PWA. This hand-rolls the two TUS requests a
/// Bunny upload actually needs (create, then one PATCH with the file's
/// bytes) using dio instead — the same "read the XFile as bytes, PUT/
/// PATCH with an onSendProgress callback" shape
/// PostService.uploadMediaWithProgress already uses for Supabase
/// Storage, which is already proven to work on every platform this app
/// ships to.
class BunnyNotConfiguredException implements Exception {}

class BunnyStreamCredentials {
  final String videoId;
  final String libraryId;
  final String uploadEndpoint;
  final String authorizationSignature;
  final int authorizationExpire;
  final String playbackUrl;
  final String thumbnailUrl;

  BunnyStreamCredentials({
    required this.videoId,
    required this.libraryId,
    required this.uploadEndpoint,
    required this.authorizationSignature,
    required this.authorizationExpire,
    required this.playbackUrl,
    required this.thumbnailUrl,
  });

  factory BunnyStreamCredentials.fromJson(Map<String, dynamic> json) => BunnyStreamCredentials(
        videoId: json['video_id'],
        libraryId: json['library_id'],
        uploadEndpoint: json['upload_endpoint'],
        authorizationSignature: json['authorization_signature'],
        authorizationExpire: json['authorization_expire'],
        playbackUrl: json['playback_url'],
        thumbnailUrl: json['thumbnail_url'],
      );

  // Bunny validates these on every POST/HEAD/PATCH against the tusupload
  // endpoint, not just the initial create call — so every request below
  // resends the full set.
  Map<String, String> get _authHeaders => {
        'AuthorizationSignature': authorizationSignature,
        'AuthorizationExpire': '$authorizationExpire',
        'LibraryId': libraryId,
        'VideoId': videoId,
      };
}

class BunnyVideoStatus {
  final bool ready;
  final bool failed;
  final String playbackUrl;
  final String thumbnailUrl;
  final int? durationSeconds;

  BunnyVideoStatus({
    required this.ready,
    required this.failed,
    required this.playbackUrl,
    required this.thumbnailUrl,
    this.durationSeconds,
  });

  factory BunnyVideoStatus.fromJson(Map<String, dynamic> json) => BunnyVideoStatus(
        ready: json['ready'] ?? false,
        failed: json['failed'] ?? false,
        playbackUrl: json['playback_url'],
        thumbnailUrl: json['thumbnail_url'],
        durationSeconds: json['duration_seconds'],
      );
}

class BunnyStreamService {
  static Future<Map<String, String>> _authedJsonHeaders() async {
    final token = SupabaseService.client.auth.currentSession?.accessToken;
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// Calls the backend to create the Bunny-side video object and get a
  /// short-lived upload credential for it. Throws
  /// [BunnyNotConfiguredException] on a 503 — the backend hasn't been
  /// given real Bunny credentials yet (see bunny_stream.py's
  /// _configured()). Callers should catch that specific case and fall
  /// back to the existing Supabase Storage upload path rather than
  /// treating it as a hard failure — this is what lets old and new
  /// videos coexist with zero Flutter-side feature flag.
  static Future<BunnyStreamCredentials> createUploadCredentials(String title) async {
    final res = await http.post(
      Uri.parse('${AiBackendConstants.baseUrl}/api/v1/videos/bunny/create'),
      headers: await _authedJsonHeaders(),
      body: jsonEncode({'title': title}),
    );
    if (res.statusCode == 503) throw BunnyNotConfiguredException();
    if (res.statusCode != 200) {
      throw Exception(_detailFrom(res) ?? 'Could not start Bunny upload (${res.statusCode})');
    }
    return BunnyStreamCredentials.fromJson(jsonDecode(res.body));
  }

  /// Pulls the backend's own `detail` message out of a non-200 response
  /// (e.g. "Create an account to use this feature." on a 403 from
  /// get_current_user_id_no_guest) instead of collapsing every failure
  /// into a bare status code — the actual reason is what tells a viewer
  /// (or whoever's debugging their report) what to do next.
  static String? _detailFrom(http.Response res) {
    try {
      final data = jsonDecode(res.body);
      final detail = data is Map ? data['detail'] : null;
      return detail is String ? detail : null;
    } catch (_) {
      return null;
    }
  }

  static String _mimeTypeFor(String filename) {
    final ext = filename.contains('.') ? filename.split('.').last.toLowerCase() : '';
    switch (ext) {
      case 'mov':
        return 'video/quicktime';
      case 'm4v':
        return 'video/x-m4v';
      case 'mp4':
      default:
        return 'video/mp4';
    }
  }

  /// Uploads [file]'s bytes straight to Bunny over TUS using the
  /// credentials from [createUploadCredentials]. [onProgress] reports
  /// 0.0-1.0. Sends the whole file as a single TUS chunk rather than
  /// looping over smaller ones — simplest correct implementation of the
  /// protocol, and no regression versus today: uploadMediaWithProgress
  /// already reads a whole video into memory before a single PUT to
  /// Supabase Storage.
  static Future<void> uploadVideo(
    XFile file,
    BunnyStreamCredentials creds, {
    void Function(double progress)? onProgress,
  }) async {
    final bytes = await file.readAsBytes();
    final dio = Dio();

    final metadata = [
      'filetype ${base64.encode(utf8.encode(_mimeTypeFor(file.name)))}',
      'title ${base64.encode(utf8.encode(file.name))}',
    ].join(',');

    final createRes = await dio.post(
      creds.uploadEndpoint,
      options: Options(
        headers: {
          ...creds._authHeaders,
          'Tus-Resumable': '1.0.0',
          'Upload-Length': '${bytes.length}',
          'Upload-Metadata': metadata,
        },
        validateStatus: (_) => true,
      ),
    );
    if ((createRes.statusCode ?? 0) < 200 || (createRes.statusCode ?? 0) >= 300) {
      throw Exception('Bunny upload could not start (${createRes.statusCode})');
    }
    final location = createRes.headers.value('location');
    if (location == null || location.isEmpty) {
      throw Exception('Bunny did not return an upload location.');
    }
    final uploadUri = Uri.parse(location).hasScheme
        ? Uri.parse(location)
        : Uri.parse(creds.uploadEndpoint).resolve(location);

    final patchRes = await dio.patch(
      uploadUri.toString(),
      data: bytes,
      options: Options(
        headers: {
          ...creds._authHeaders,
          'Tus-Resumable': '1.0.0',
          'Upload-Offset': '0',
          'Content-Type': 'application/offset+octet-stream',
        },
        validateStatus: (_) => true,
      ),
      onSendProgress: (sent, total) {
        if (total > 0) onProgress?.call(sent / total);
      },
    );
    if ((patchRes.statusCode ?? 0) < 200 || (patchRes.statusCode ?? 0) >= 300) {
      throw Exception('Bunny upload failed (${patchRes.statusCode})');
    }
  }

  /// Polls the backend for Bunny's processing status. Throws
  /// [BunnyNotConfiguredException] on a 503, same as above.
  static Future<BunnyVideoStatus> getStatus(String videoId) async {
    final res = await http.get(
      Uri.parse('${AiBackendConstants.baseUrl}/api/v1/videos/bunny/$videoId/status'),
      headers: await _authedJsonHeaders(),
    );
    if (res.statusCode == 503) throw BunnyNotConfiguredException();
    if (res.statusCode != 200) {
      throw Exception('Could not check Bunny video status (${res.statusCode})');
    }
    return BunnyVideoStatus.fromJson(jsonDecode(res.body));
  }

  /// Polls [getStatus] until Bunny finishes processing (ready or
  /// failed) or [timeout] elapses. Returns null on timeout so the
  /// caller can decide how to handle a video that's still processing
  /// after a long wait (e.g. publish anyway and let it flip to ready
  /// later) rather than hanging the UI forever.
  static Future<BunnyVideoStatus?> waitForReady(
    String videoId, {
    Duration timeout = const Duration(minutes: 10),
    Duration pollInterval = const Duration(seconds: 3),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final status = await getStatus(videoId);
      if (status.ready || status.failed) return status;
      await Future.delayed(pollInterval);
    }
    return null;
  }
}
