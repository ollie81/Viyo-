import '../models/post.dart';
import '../models/series.dart';
import 'post_service.dart';
import 'supabase_service.dart';

/// "Save for later" — a series or a post, kept in the generic
/// `watchlist` table (same target_type/target_id shape the `reports`
/// table already uses). Phase 2 table — every read here fails safe to
/// an empty/false result if it doesn't exist yet, same "inert until
/// migrated" posture as series_follows.
class WatchlistService {
  static final _client = SupabaseService.client;

  static Future<bool> isSaved(String userId, String targetType, String targetId) async {
    try {
      final row = await _client
          .from('watchlist')
          .select('id')
          .eq('user_id', userId)
          .eq('target_type', targetType)
          .eq('target_id', targetId)
          .maybeSingle();
      return row != null;
    } catch (_) {
      return false;
    }
  }

  static Future<void> add(String userId, String targetType, String targetId) async {
    await _client.from('watchlist').insert({
      'user_id': userId,
      'target_type': targetType,
      'target_id': targetId,
    });
  }

  static Future<void> remove(String userId, String targetType, String targetId) async {
    await _client
        .from('watchlist')
        .delete()
        .eq('user_id', userId)
        .eq('target_type', targetType)
        .eq('target_id', targetId);
  }

  /// Saved series, most-recently-saved first — a saved id that no
  /// longer resolves to a real series (deleted) is silently dropped
  /// rather than shown as a broken tile.
  static Future<List<Series>> getSavedSeries(String userId) async {
    try {
      final ids = await _savedTargetIds(userId, 'series');
      if (ids.isEmpty) return [];
      final seriesData = await _client
          .from('series')
          .select('*, profiles(username, display_name, avatar_url)')
          .inFilter('id', ids);
      final byId = {
        for (final row in (seriesData as List)) row['id'] as String: Series.fromJson(row),
      };
      return ids.map((id) => byId[id]).whereType<Series>().toList();
    } catch (_) {
      return [];
    }
  }

  /// Saved posts, most-recently-saved first — same dropped-if-missing
  /// behavior as getSavedSeries.
  static Future<List<Post>> getSavedPosts(String userId) async {
    try {
      final ids = await _savedTargetIds(userId, 'post');
      if (ids.isEmpty) return [];
      final posts = await PostService.getPostsByIds(ids);
      final byId = {for (final p in posts) p.id: p};
      return ids.map((id) => byId[id]).whereType<Post>().toList();
    } catch (_) {
      return [];
    }
  }

  static Future<List<String>> _savedTargetIds(String userId, String targetType) async {
    final rows = await _client
        .from('watchlist')
        .select('target_id')
        .eq('user_id', userId)
        .eq('target_type', targetType)
        .order('created_at', ascending: false);
    return (rows as List).map((r) => r['target_id'] as String).toList();
  }
}
