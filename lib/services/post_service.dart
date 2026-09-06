import 'dart:io';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:video_thumbnail/video_thumbnail.dart' as vt;
import '../constants/supabase_constants.dart';
import '../models/post.dart';
import '../models/post_feedback.dart';
import 'supabase_service.dart';

class PostService {
  static final _client = SupabaseService.client;

  // How many of the most recent posts to pull back and rank client-side.
  // At Viyo's current scale this comfortably covers the whole table, so
  // this is effectively "rank everything" — cheap because it's one query
  // and no server-side compute, not because it's a small sample. Revisit
  // (DB-side ranking, or a real recommender) once post volume outgrows
  // fetching this many rows on every feed load.
  static const int _feedRankingPoolSize = 150;

  // A followed creator's posts are boosted, not guaranteed top — the
  // multiplier still decays with the post's own age/engagement via
  // _hotScore, so an old followed post doesn't permanently outrank
  // everything else just because you follow that person.
  static const double _followBoostMultiplier = 3.0;

  // A paid boost (see boostPost below) — stronger than the follow boost
  // since it's a deliberate coin spend, not just an implicit signal.
  // No expiry timestamp needed: is_boosted just stays true, and
  // _hotScore's own age/engagement decay is what keeps an old boosted
  // post from dominating the feed forever.
  static const double _boostMultiplier = 4.0;

  /// Reddit-style "hot" score: recent + engaged beats merely recent.
  /// A post with zero engagement yet is ranked by recency alone (so a
  /// brand-new post still gets a fair first look — the classic
  /// hot-ranking cold-start problem, worth avoiding on an app whose whole
  /// pitch is helping new creators get seen) rather than scoring 0 and
  /// sinking behind every older post that has even a single like.
  static double _hotScore(Post post) {
    final ageHours = DateTime.now().difference(post.createdAt).inMinutes / 60.0;
    final engagement = post.likeCount + post.commentCount * 2;
    if (engagement <= 0) return 1 / (ageHours + 1);
    return engagement / pow(ageHours + 2, 1.5);
  }

  /// Stamps the real "did I like this" state onto each post. Every feed
  /// query previously just selected `*` from `posts` and relied on
  /// Post.fromJson's `liked_by_me` field — but nothing ever actually
  /// computed or returned that column, so it silently defaulted to
  /// false on every single fetch. That's the root of "my like
  /// disappears after I move to the next video": the like itself may
  /// have saved fine, but every subsequent feed reload re-fetched posts
  /// with likedByMe hard-wired to false, resetting the heart icon.
  static Future<List<Post>> _withLikedByMe(List<Post> posts) async {
    final userId = SupabaseService.currentUserId;
    if (userId == null || posts.isEmpty) return posts;
    try {
      final liked = await _client
          .from('likes')
          .select('post_id')
          .eq('user_id', userId)
          .inFilter('post_id', posts.map((p) => p.id).toList());
      final likedIds = (liked as List).map((r) => r['post_id'] as String).toSet();
      return posts.map((p) => p.copyWith(likedByMe: likedIds.contains(p.id))).toList();
    } catch (_) {
      // Best-effort — a failed lookup here should mean hearts don't
      // reflect reality, not that the whole feed fails to load.
      return posts;
    }
  }

  /// Home feed, ranked instead of just newest-first: a lightweight "hot"
  /// score (recency decayed by engagement, see _hotScore) with boosts for
  /// creators the viewer already follows and for posts the owner paid
  /// coins to boost (see boostPost below). Pinned posts still always
  /// lead, unchanged from before.
  ///
  /// This re-ranks a bounded recent pool client-side rather than doing a
  /// true DB-side paginated query — fine at Viyo's current scale (see
  /// _feedRankingPoolSize) and avoids needing a new Postgres function or
  /// materialized ranking column for a first pass.
  static Future<List<Post>> getFeed({int limit = 20, int offset = 0}) async {
    final data = await _client
        .from('posts')
        .select('*, profiles(username, display_name, avatar_url)')
        .eq('is_private', false)
        .eq('is_archived', false)
        .order('created_at', ascending: false)
        .limit(_feedRankingPoolSize);
    final posts = await _withLikedByMe((data as List).map((e) => Post.fromJson(e)).toList());

    Set<String> followedIds = {};
    final userId = SupabaseService.currentUserId;
    if (userId != null) {
      try {
        final follows = await _client
            .from('follows')
            .select('following_id')
            .eq('follower_id', userId);
        followedIds = (follows as List).map((f) => f['following_id'] as String).toSet();
      } catch (_) {
        // Follow-boost is a nice-to-have — falling back to plain hot
        // ranking beats failing the whole feed load over this.
      }
    }

    double rankScore(Post p) {
      var score = _hotScore(p);
      if (p.isBoosted) score *= _boostMultiplier;
      if (followedIds.contains(p.userId)) score *= _followBoostMultiplier;
      return score;
    }

    final pinned = posts.where((p) => p.isPinned).toList();
    final rest = posts.where((p) => !p.isPinned).toList()
      ..sort((a, b) => rankScore(b).compareTo(rankScore(a)));

    final ranked = [...pinned, ...rest];
    final start = offset.clamp(0, ranked.length);
    final end = (offset + limit).clamp(0, ranked.length);
    return ranked.sublist(start, end);
  }

  /// A profile's posts as seen by the *owner* — includes private/archived
  /// posts so they can manage them. For viewing someone else's profile,
  /// use [getPublicUserPosts] instead, which respects privacy.
  static Future<List<Post>> getUserPosts(String userId) async {
    final data = await _client
        .from('posts')
        .select('*, profiles(username, display_name, avatar_url)')
        .eq('user_id', userId)
        .order('is_pinned', ascending: false)
        .order('created_at', ascending: false);
    return _withLikedByMe((data as List).map((e) => Post.fromJson(e)).toList());
  }

  /// A profile's posts as seen by *anyone else* — hides private and
  /// archived posts, since those should only be visible to the owner.
  static Future<List<Post>> getPublicUserPosts(String userId) async {
    final data = await _client
        .from('posts')
        .select('*, profiles(username, display_name, avatar_url)')
        .eq('user_id', userId)
        .eq('is_private', false)
        .eq('is_archived', false)
        .order('is_pinned', ascending: false)
        .order('created_at', ascending: false);
    return _withLikedByMe((data as List).map((e) => Post.fromJson(e)).toList());
  }

  static Future<void> setPrivate(String postId, bool isPrivate) async {
    await _client.from('posts').update({'is_private': isPrivate}).eq('id', postId);
  }

  static Future<void> setArchived(String postId, bool isArchived) async {
    await _client.from('posts').update({'is_archived': isArchived}).eq('id', postId);
  }

  static Future<void> setPinned(String postId, bool isPinned) async {
    await _client.from('posts').update({'is_pinned': isPinned}).eq('id', postId);
  }

  /// Video-only feed for the full-screen Shorts-style player.
  static Future<List<Post>> getVideoFeed({int limit = 20, int offset = 0}) async {
    final data = await _client
        .from('posts')
        .select('*, profiles(username, display_name, avatar_url)')
        .eq('post_type', 'video')
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
    return _withLikedByMe((data as List).map((e) => Post.fromJson(e)).toList());
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

  /// Bypasses the old `like_post` Postgres RPC, which crashed server-side
  /// (`column "post_id" of relation "notifications" does not exist`)
  /// trying to insert a notification row against a column that was
  /// never actually on that table — confirmed against
  /// NotificationService's own working queries, which only ever
  /// reference id/user_id/actor_id/type/message/is_read/created_at.
  /// Likely why every like silently failed. Reimplemented directly,
  /// same pattern as boost_post/spotlight elsewhere in this app: don't
  /// trust an opaque RPC you can't inspect, do the steps yourself
  /// against columns already verified in use.
  static Future<void> likePost(String userId, String postId) async {
    try {
      await _client.from('likes').insert({'user_id': userId, 'post_id': postId});
    } on PostgrestException catch (e) {
      // Unique-violation — already liked (e.g. a stale double-tap).
      // Nothing left to do; the count is already right.
      if (e.code == '23505') return;
      rethrow;
    }

    // Compare-and-swap increment instead of a blind +1 write, so two
    // concurrent likes on the same post can't race and drop a count —
    // same tradeoff already used server-side for coin balances.
    final current = await _client.from('posts').select('like_count').eq('id', postId).single();
    final currentCount = (current['like_count'] as num?)?.toInt() ?? 0;
    await _client
        .from('posts')
        .update({'like_count': currentCount + 1})
        .eq('id', postId)
        .eq('like_count', currentCount);

    // Best-effort notification — never let this fail the like itself.
    try {
      final post = await _client.from('posts').select('user_id').eq('id', postId).single();
      final postOwnerId = post['user_id'] as String?;
      if (postOwnerId != null && postOwnerId != userId) {
        final actor = await _client
            .from('profiles')
            .select('display_name, username')
            .eq('id', userId)
            .maybeSingle();
        final actorName = actor?['display_name'] ?? actor?['username'] ?? 'Someone';
        await _client.from('notifications').insert({
          'user_id': postOwnerId,
          'actor_id': userId,
          'type': 'like',
          'message': '$actorName liked your post',
        });
      }
    } catch (_) {}
  }

  static Future<void> unlikePost(String userId, String postId) async {
    await _client.from('likes').delete().eq('user_id', userId).eq('post_id', postId);

    // Same compare-and-swap approach as likePost, and for the same
    // reason: one less opaque RPC this app depends on without being
    // able to see what it actually does.
    final current = await _client.from('posts').select('like_count').eq('id', postId).single();
    final currentCount = (current['like_count'] as num?)?.toInt() ?? 0;
    if (currentCount <= 0) return;
    await _client
        .from('posts')
        .update({'like_count': currentCount - 1})
        .eq('id', postId)
        .eq('like_count', currentCount);
  }

  static Future<void> toggleLike(Post post) async {
    final userId = SupabaseService.currentUserId;
    if (userId == null) return;
    if (post.likedByMe) {
      await unlikePost(userId, post.id);
    } else {
      await likePost(userId, post.id);
    }
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
