import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants/supabase_constants.dart';
import '../models/post.dart';
import 'bunny_stream_service.dart';
import 'supabase_service.dart';

/// Server-side video metadata — real width/height/duration and a
/// generated thumbnail for ANY uploaded video, independent of whether a
/// browser successfully captured a frame client-side. See
/// viyo_ai's video_metadata.py for the actual ffprobe/ffmpeg work; this
/// is just the thin HTTP wrapper every call site below shares, so Web
/// and Android both end up calling the exact same backend logic rather
/// than each platform running its own capture path.
class VideoMetadataService {
  static Map<String, String> _headers() {
    final token = SupabaseService.client.auth.currentSession?.accessToken;
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// Fire-and-forget: call right after a Supabase-hosted video post is
  /// created (a Bunny-hosted one gets its width/height for free from
  /// Bunny's own API instead — see bunny_stream.py's self-heal, so this
  /// never needs calling for those). Never throws — a failed probe just
  /// leaves width/height null, same as before this existed.
  static Future<void> probeDimensions({required String postId, required String mediaUrl}) async {
    try {
      await http.post(
        Uri.parse('${AiBackendConstants.baseUrl}/api/v1/videos/probe-dimensions'),
        headers: _headers(),
        body: jsonEncode({'post_id': postId, 'media_url': mediaUrl}),
      );
    } catch (_) {}
  }

  /// Server-side fallback thumbnail generator — ffmpeg extracts a real
  /// frame directly off the video's own URL. Used whenever a post ends
  /// up with no thumbnail_url after upload (the client-side capture
  /// failed, was skipped, or — on web specifically — hit a CORS-tainted-
  /// canvas error), and by SeriesService's own cover backfill instead of
  /// asking a viewer's browser to capture a remote frame. Pass [postId]
  /// to also persist the result onto that post's own thumbnail_url;
  /// omit it (as the series-cover backfill does) to just get the URL
  /// back without writing it anywhere. Returns null on any failure —
  /// callers already treat a missing thumbnail as a normal, handled
  /// state, not an error.
  static Future<String?> generateThumbnail({required String mediaUrl, String? postId}) async {
    try {
      final res = await http.post(
        Uri.parse('${AiBackendConstants.baseUrl}/api/v1/videos/thumbnail/generate'),
        headers: _headers(),
        body: jsonEncode({'media_url': mediaUrl, if (postId != null) 'post_id': postId}),
      );
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return data['thumbnail_url'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Fire-and-forget: call whenever a video post is actually opened and
  /// its width/height still read null — covers every post uploaded
  /// before this backfill existed, and (the gap this was actually
  /// written to close) a Bunny-hosted post that's already playing fine
  /// today: bunny_stream.py's width/height self-heal only runs inside
  /// get_bunny_video_status, which a healthy, already-"ready" post never
  /// calls during normal playback — only the processing-poll and
  /// broken-URL-retry paths did. Calling getStatus here, once, the
  /// first time anyone actually opens such a post, is what makes that
  /// self-heal actually fire for it. No-ops once width/height are set.
  static void ensureDimensions(Post post) {
    if (post.width != null && post.height != null) return;
    if (post.bunnyVideoId != null) {
      unawaited(_tryGetBunnyStatus(post.bunnyVideoId!));
    } else if (post.mediaUrl != null) {
      unawaited(probeDimensions(postId: post.id, mediaUrl: post.mediaUrl!));
    }
  }

  static Future<void> _tryGetBunnyStatus(String videoId) async {
    try {
      await BunnyStreamService.getStatus(videoId);
    } catch (_) {}
  }
}
