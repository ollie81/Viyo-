import 'dart:io';
import 'package:uuid/uuid.dart';
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

  static Future<String> uploadMedia(File file, String userId) async {
    final ext = file.path.split('.').last;
    final path = '$userId/${const Uuid().v4()}.$ext';
    await _client.storage
        .from(SupabaseConstants.postsBucket)
        .upload(path, file);
    return _client.storage.from(SupabaseConstants.postsBucket).getPublicUrl(path);
  }

  static Future<Post> createPost({
    required String userId,
    required PostType type,
    String caption = '',
    String? mediaUrl,
    int? durationSeconds,
  }) async {
    final inserted = await _client
        .from('posts')
        .insert({
          'user_id': userId,
          'post_type': type.name,
          'caption': caption,
          'media_url': mediaUrl,
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
