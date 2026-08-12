import '../models/user_profile.dart';
import '../models/creator_stats.dart';
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
    return await _client.rpc('follow_user', params: {
      'p_follower_id': followerId,
      'p_following_id': followingId,
    });
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
