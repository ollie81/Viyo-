import '../models/user_profile.dart';
import '../models/creator_stats.dart';
import 'analytics_service.dart';
import 'discover_spotlight_service.dart';
import 'moderation_service.dart';
import 'supabase_service.dart';

class ProfileService {
  static final _client = SupabaseService.client;

  static Future<UserProfile> getProfile(String userId) async {
    final data =
        await _client.from('profiles').select().eq('id', userId).single();
    return UserProfile.fromJson(data);
  }

  static Future<UserProfile?> getProfileByUsername(String username) async {
    final data = await _client
        .from('profiles')
        .select()
        .eq('username', username)
        .maybeSingle();
    return data == null ? null : UserProfile.fromJson(data);
  }

  static Future<void> updateProfile({
    required String userId,
    String? displayName,
    String? bio,
    String? niche,
    String? avatarUrl,
  }) async {
    final updates = <String, dynamic>{'updated_at': DateTime.now().toIso8601String()};
    if (displayName != null) updates['display_name'] = displayName;
    if (bio != null) updates['bio'] = bio;
    if (niche != null) updates['niche'] = niche;
    if (avatarUrl != null) updates['avatar_url'] = avatarUrl;

    await _client.from('profiles').update(updates).eq('id', userId);
  }

  static Future<List<Map<String, dynamic>>> searchCreators(String query) async {
    return await _client
        .from('profiles')
        .select('id, username, display_name, avatar_url, niche')
        .or('username.ilike.%$query%,display_name.ilike.%$query%')
        .limit(20);
  }

  /// Populates the Discover tab before anyone types a search, instead of
  /// a blank screen that only ever does something once you already know
  /// who you're looking for. Beyond that there's still no engagement
  /// data denormalized onto profiles to rank by (guessing a column that
  /// doesn't exist would just trade an empty screen for a crash) — the
  /// one exception is Discover Spotlight (see DiscoverSpotlightService),
  /// a paid, self-expiring placement boost, which pulls spotlighted
  /// creators to the front; everyone else keeps the original query order.
  static Future<List<Map<String, dynamic>>> getSuggestedCreators({
    required String excludeUserId,
    int limit = 30,
  }) async {
    // Fetch a larger candidate pool than `limit` so a spotlighted
    // creator who wouldn't otherwise land in the first `limit` rows
    // still gets pulled to the front instead of being missed entirely.
    final candidates = await _client
        .from('profiles')
        .select('id, username, display_name, avatar_url, niche')
        .neq('id', excludeUserId)
        .limit(limit * 4);
    var pool = List<Map<String, dynamic>>.from(candidates);

    final hidden = await ModerationService.getHiddenUserIds(excludeUserId);
    if (hidden.isNotEmpty) {
      pool = pool.where((c) => !hidden.contains(c['id'])).toList();
    }

    List<String> spotlightedIds = const [];
    try {
      spotlightedIds = await DiscoverSpotlightService.getActiveSpotlightIds();
    } catch (_) {
      // Spotlight ordering is a nice-to-have — an unranked list beats
      // failing Discover entirely over this.
    }

    if (spotlightedIds.isEmpty) return pool.take(limit).toList();

    final spotlightedSet = spotlightedIds.toSet();
    final byId = {for (final c in pool) c['id'] as String: c};
    final spotlightedFirst = [
      for (final id in spotlightedIds)
        if (byId.containsKey(id)) byId[id]!,
    ];
    final rest = pool.where((c) => !spotlightedSet.contains(c['id'])).toList();
    return [...spotlightedFirst, ...rest].take(limit).toList();
  }

  static Future<int> getFollowerCount(String userId) async {
    final res = await _client
        .from('follows')
        .select('id')
        .eq('following_id', userId)
        .count();
    return res.count;
  }

  static Future<int> getFollowingCount(String userId) async {
    final res = await _client
        .from('follows')
        .select('id')
        .eq('follower_id', userId)
        .count();
    return res.count;
  }

  static Future<bool> isFollowing(String followerId, String followingId) async {
    final row = await _client
        .from('follows')
        .select('id')
        .eq('follower_id', followerId)
        .eq('following_id', followingId)
        .maybeSingle();
    return row != null;
  }

  static Future<Map<String, dynamic>> follow(String followerId, String followingId) async {
    final result = await _client.rpc('follow_user', params: {
      'p_follower_id': followerId,
      'p_following_id': followingId,
    });
    AnalyticsService.track('user_followed', properties: {'followed_id': followingId});
    return result;
  }

  static Future<void> unfollow(String followerId, String followingId) async {
    await _client
        .from('follows')
        .delete()
        .eq('follower_id', followerId)
        .eq('following_id', followingId);
  }

  /// Spends coins to unlock the Premium/Verified badge. Server-enforced via
  /// the `purchase_premium` RPC so it can't be granted by editing the client.
  static Future<Map<String, dynamic>> purchasePremium({
    required String userId,
    required double cost,
  }) async {
    return await _client.rpc('purchase_premium', params: {
      'p_user_id': userId,
      'p_cost': cost,
    });
  }

  /// Backs the Creator Growth Dashboard — one RPC call instead of the
  /// client stitching together several separate queries.
  static Future<CreatorStats> getCreatorStats(String userId) async {
    final data = await _client.rpc('get_creator_stats', params: {'p_user_id': userId});
    return CreatorStats.fromJson(data as Map<String, dynamic>);
  }
}
