import '../models/engagement_event.dart';
import 'supabase_service.dart';

/// Builds the "Who's Engaging With You" digest from real interactions on
/// the creator's own posts — new followers, comments, and likes. Every
/// query here is scoped to tables/columns already used elsewhere in the
/// app (comments, follows, likes, posts, profiles); likes/follows are
/// fetched with a plain select (never a nested `profiles(...)` join,
/// since that relationship isn't established anywhere else in the
/// codebase) and ordering by created_at is attempted but falls back to
/// an unordered fetch if that column turns out not to be queryable —
/// this digest should never be the reason the app crashes.
class EngagementService {
  static final _client = SupabaseService.client;

  static Future<List<EngagementEvent>> getRecentActivity(
    String userId, {
    int limit = 15,
  }) async {
    final myPosts = await _client
        .from('posts')
        .select('id,caption')
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(50);
    final myPostIds = (myPosts as List).map((p) => p['id'] as String).toList();
    final captionByPostId = {for (final p in myPosts) p['id'] as String: p['caption'] as String?};

    final events = <EngagementEvent>[];

    // Comments — post_id/user_id/created_at and the profiles join are all
    // already used by PostService.getComments, so this is verified-safe.
    if (myPostIds.isNotEmpty) {
      try {
        final comments = await _client
            .from('comments')
            .select('user_id,post_id,created_at,profiles(username,display_name,avatar_url)')
            .inFilter('post_id', myPostIds)
            .order('created_at', ascending: false)
            .limit(10);
        for (final c in comments) {
          final profile = c['profiles'] as Map<String, dynamic>?;
          if (profile == null) continue;
          events.add(EngagementEvent(
            type: EngagementType.comment,
            actorId: c['user_id'] as String,
            actorUsername: profile['username'] ?? '',
            actorDisplayName: profile['display_name'] ?? 'Someone',
            actorAvatarUrl: profile['avatar_url'],
            occurredAt: DateTime.tryParse(c['created_at'] ?? ''),
            postCaption: captionByPostId[c['post_id']],
          ));
        }
      } catch (_) {
        // Comments digest is a nice-to-have — never block the rest.
      }

      final likeRows = await _fetchWithOptionalOrder(
        table: 'likes',
        select: 'user_id,post_id,created_at',
        column: 'post_id',
        values: myPostIds,
        limit: 10,
      );
      if (likeRows.isNotEmpty) {
        final actorIds = likeRows.map((r) => r['user_id'] as String).toSet().toList();
        final profiles = await _profilesById(actorIds);
        for (final r in likeRows) {
          final profile = profiles[r['user_id']];
          if (profile == null) continue;
          events.add(EngagementEvent(
            type: EngagementType.like,
            actorId: r['user_id'] as String,
            actorUsername: profile['username'] ?? '',
            actorDisplayName: profile['display_name'] ?? 'Someone',
            actorAvatarUrl: profile['avatar_url'],
            occurredAt: r['created_at'] != null ? DateTime.tryParse(r['created_at']) : null,
            postCaption: captionByPostId[r['post_id']],
          ));
        }
      }
    }

    // New followers.
    final followRows = await _fetchWithOptionalOrder(
      table: 'follows',
      select: 'follower_id,created_at',
      column: 'following_id',
      values: [userId],
      limit: 10,
    );
    if (followRows.isNotEmpty) {
      final actorIds = followRows.map((r) => r['follower_id'] as String).toSet().toList();
      final profiles = await _profilesById(actorIds);
      for (final r in followRows) {
        final profile = profiles[r['follower_id']];
        if (profile == null) continue;
        events.add(EngagementEvent(
          type: EngagementType.follow,
          actorId: r['follower_id'] as String,
          actorUsername: profile['username'] ?? '',
          actorDisplayName: profile['display_name'] ?? 'Someone',
          actorAvatarUrl: profile['avatar_url'],
          occurredAt: r['created_at'] != null ? DateTime.tryParse(r['created_at']) : null,
        ));
      }
    }

    events.sort((a, b) {
      if (a.occurredAt == null && b.occurredAt == null) return 0;
      if (a.occurredAt == null) return 1;
      if (b.occurredAt == null) return -1;
      return b.occurredAt!.compareTo(a.occurredAt!);
    });

    return events.take(limit).toList();
  }

  /// Tries an ordered-by-created_at fetch first; if the column turns out
  /// not to exist or isn't orderable, retries the same filter unordered
  /// rather than surfacing an error from what's meant to be a passive
  /// activity digest.
  static Future<List<Map<String, dynamic>>> _fetchWithOptionalOrder({
    required String table,
    required String select,
    required String column,
    required List<String> values,
    required int limit,
  }) async {
    try {
      final rows = await _client
          .from(table)
          .select(select)
          .inFilter(column, values)
          .order('created_at', ascending: false)
          .limit(limit);
      return List<Map<String, dynamic>>.from(rows);
    } catch (_) {
      try {
        final rows = await _client.from(table).select(select).inFilter(column, values).limit(limit);
        return List<Map<String, dynamic>>.from(rows);
      } catch (_) {
        return const [];
      }
    }
  }

  static Future<Map<String, Map<String, dynamic>>> _profilesById(List<String> ids) async {
    if (ids.isEmpty) return {};
    final rows = await _client
        .from('profiles')
        .select('id,username,display_name,avatar_url')
        .inFilter('id', ids);
    return {for (final p in rows) p['id'] as String: p};
  }
}
