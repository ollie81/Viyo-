import 'dart:io';
import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';
import 'package:video_thumbnail/video_thumbnail.dart' as vt;
import '../constants/supabase_constants.dart';
import '../models/post.dart';
import '../models/post_feedback.dart';
import 'supabase_service.dart';

class PostService {
  static final _client = SupabaseService.client;

  /// Home feed: posts from followed users + some recommended (simplified:
  /// most recent posts overall, since a real recommender is out of scope
  /// for v1). Swap the query for a `following` filter once you want a
  /// strict "following only" feed.
  static Future<List<Post>> getFeed({int limit = 20, int offset = 0}) async {
    final data = await _client
        .from('posts')
        .select('*, profiles(username, display_name, avatar_url)')
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
    return (data as List).map((e) => Post.fromJson(e)).toList();
  }

  static Future<List<Post>> getUserPosts(String userId) async {
    final data = await _client
        .from('posts')
        .select('*, profiles(username, display_name, avatar_url)')
        .eq('user_id', userId)
        .order('created_at', ascending: false);
    return (data as List).map((e) => Post.fromJson(e)).toList();
  }

  /// Video-only feed for the full-screen Shorts-style player.
  static Future<List<Post>> getVideoFeed({int limit = 20, int offset = 0}) async {
    final data = await _client
        .from('posts')
        .select('*, profiles(username, display_name, avatar_url)')
        .eq('post_type', 'video')
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
    return (data as List).map((e) => Post.fromJson(e)).toList();
  }

  static Future<String> uploadMedia(File file, String userId) async {
    final ext = file.path.split('.').last;
    final path = '$userId/${const Uuid().v4()}.$ext';
    await _client.storage
        .from(SupabaseConstants.postsBucket)
        .upload(path, file);
    return _client.storage.from(SupabaseConstants.postsBucket).getPublicUrl(path);
  }

  static String _mimeTypeFor(String ext) {
    switch (ext.toLowerCase()) {
      case 'mp4':
      case 'mov':
      case 'm4v':
        return 'video/mp4';
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
      default:
        return 'image/jpeg';
    }
  }

  /// Same as [uploadMedia] but reports upload progress (0.0-1.0) so the UI
  /// can show a percentage instead of a plain spinner. Uses dio directly
  /// against Supabase Storage's REST endpoint since supabase_flutter's
  /// convenience `.upload()` doesn't expose progress callbacks.
  static Future<String> uploadMediaWithProgress(
    File file,
    String userId, {
    void Function(double progress)? onProgress,
  }) async {
    final ext = file.path.split('.').last;
    final path = '$userId/${const Uuid().v4()}.$ext';
    final bytes = await file.readAsBytes();
    final token = _client.auth.currentSession?.accessToken;

    final url =
        '${SupabaseConstants.url}/storage/v1/object/${SupabaseConstants.postsBucket}/$path';

    final dio = Dio();
    await dio.put(
      url,
      data: bytes,
      options: Options(
        headers: {
          'Authorization': 'Bearer $token',
          'apikey': SupabaseConstants.anonKey,
          'Content-Type': _mimeTypeFor(ext),
        },
      ),
      onSendProgress: (sent, total) {
        if (total > 0) onProgress?.call(sent / total);
      },
    );

    return _client.storage.from(SupabaseConstants.postsBucket).getPublicUrl(path);
  }

  /// Extracts a single frame from a video file as a JPEG, uploads it, and
  /// returns its public URL. This is what lets the AI Creator Coach
  /// actually "see" video posts — GPT-4o's vision input takes images, not
  /// video streams, so a representative frame stands in for the video.
  static Future<String?> generateAndUploadVideoThumbnail(File videoFile, String userId) async {
    try {
      final thumbPath = await vt.VideoThumbnail.thumbnailFile(
        video: videoFile.path,
        imageFormat: vt.ImageFormat.JPEG,
        maxWidth: 720,
        quality: 75,
        timeMs: 500, // ~0.5s in — skips a possible black opening frame
      );
      if (thumbPath == null) return null;
      return await uploadMedia(File(thumbPath), userId);
    } catch (_) {
      // Thumbnail generation is a nice-to-have for the coach, not a
      // requirement for posting — fail silently and fall back to
      // caption-only analysis.
      return null;
    }
  }

  static Future<Post> createPost({
    required String userId,
    required PostType type,
    String caption = '',
    String? mediaUrl,
    String? thumbnailUrl,
    int? durationSeconds,
  }) async {
    final inserted = await _client
        .from('posts')
        .insert({
          'user_id': userId,
          'post_type': type.name,
          'caption': caption,
          'media_url': mediaUrl,
          'thumbnail_url': thumbnailUrl,
          'duration_seconds': durationSeconds,
        })
        .select()
        .single();

    // Award coins for posting via RPC (server-side, tamper-proof).
    await _client.rpc('award_post_creation', params: {
      'p_user_id': userId,
      'p_post_id': inserted['id'],
      'p_post_type': type.name,
    });

    return Post.fromJson(inserted);
  }

  /// Deletes a post: removes the media file(s) from storage first, then
  /// the database row. Only the post owner should ever call this — the
  /// storage RLS policy and a `posts` RLS delete policy enforce that
  /// server-side too, so this can't be bypassed by editing the client.
  static Future<void> deletePost(Post post) async {
    final pathsToRemove = <String>[];
    for (final url in [post.mediaUrl, post.thumbnailUrl]) {
      if (url == null) continue;
      // Public URLs look like: .../storage/v1/object/public/<bucket>/<path>
      final marker = '${SupabaseConstants.postsBucket}/';
      final idx = url.indexOf(marker);
      if (idx != -1) {
        pathsToRemove.add(url.substring(idx + marker.length));
      }
    }
    if (pathsToRemove.isNotEmpty) {
      await _client.storage.from(SupabaseConstants.postsBucket).remove(pathsToRemove);
    }
    await _client.from('posts').delete().eq('id', post.id);
  }

  static Future<Map<String, dynamic>> likePost(String userId, String postId) async {
    return await _client.rpc('like_post', params: {
      'p_user_id': userId,
      'p_post_id': postId,
    });
  }

  static Future<void> unlikePost(String userId, String postId) async {
    await _client.from('likes').delete().eq('user_id', userId).eq('post_id', postId);
    await _client.rpc('decrement_like_count', params: {'p_post_id': postId});
  }

  static Future<List<Map<String, dynamic>>> getComments(String postId) async {
    return await _client
        .from('comments')
        .select('*, profiles(username, display_name, avatar_url)')
        .eq('post_id', postId)
        .order('created_at');
  }

  static Future<Map<String, dynamic>> addComment({
    required String postId,
    required String userId,
    required String content,
  }) async {
    final comment = await _client
        .from('comments')
        .insert({'post_id': postId, 'user_id': userId, 'content': content})
        .select()
        .single();

    await _client.rpc('award_comment', params: {
      'p_user_id': userId,
      'p_post_id': postId,
      'p_comment_length': content.trim().length,
    });

    return comment;
  }

  /// Persists the AI Creator Coach's feedback for a post so it can be
  /// revisited later from the dashboard/post history, not just shown once.
  static Future<void> saveAiFeedback(PostFeedback feedback, {
    required String postId,
    required String userId,
  }) async {
    await _client.from('post_ai_feedback').insert(
      feedback.toDbRow(postId: postId, userId: userId),
    );
  }
}
