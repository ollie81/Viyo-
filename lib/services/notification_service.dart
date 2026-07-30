import 'supabase_service.dart';

class NotificationService {
  static final _client = SupabaseService.client;

  static Future<List<Map<String, dynamic>>> getNotifications(String userId) async {
    return await _client
        .from('notifications')
        .select('*, actor:actor_id(username, display_name, avatar_url)')
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(50);
  }

  static Future<void> markRead(String notificationId) async {
    await _client
        .from('notifications')
        .update({'is_read': true})
        .eq('id', notificationId);
  }

  static Future<int> getUnreadCount(String userId) async {
    final res = await _client
        .from('notifications')
        .select('id')
        .eq('user_id', userId)
        .eq('is_read', false)
        .count();
    return res.count;
  }
}
