import '../models/transaction.dart';
import '../models/app_badge.dart';
import 'supabase_service.dart';

/// All coin math happens server-side via Postgres RPCs (see supabase/schema.sql).
/// The client only ever reads balances/history — it never increments/decrements
/// points_balance directly. This prevents users from editing their own balance
/// by tampering with client requests.
class CoinService {
  static final _client = SupabaseService.client;

  static Future<List<CoinTransaction>> getTransactions(String userId,
      {int limit = 30}) async {
    final data = await _client
        .from('transactions')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(limit);
    return (data as List).map((e) => CoinTransaction.fromJson(e)).toList();
  }

  static Future<Map<String, dynamic>> claimDailyCheckin(String userId) async {
    return await _client.rpc('claim_daily_checkin', params: {
      'p_user_id': userId,
    });
  }

  static Future<Map<String, dynamic>> giftCoins({
    required String senderId,
    required String receiverId,
    required double amount,
  }) async {
    return await _client.rpc('gift_coins', params: {
      'p_sender_id': senderId,
      'p_receiver_id': receiverId,
      'p_amount': amount,
    });
  }

  static Future<List<AppBadge>> getStoreBadges(String userId) async {
    final badges = await _client.from('badges').select().order('tier');
    final owned = await _client
        .from('user_badges')
        .select('badge_id')
        .eq('user_id', userId);
    final ownedIds = (owned as List).map((e) => e['badge_id']).toSet();

    return (badges as List)
        .map((b) => AppBadge.fromJson({
              ...b,
              'unlocked': ownedIds.contains(b['id']),
            }))
        .toList();
  }

  static Future<Map<String, dynamic>> purchaseBadge({
    required String userId,
    required String badgeId,
  }) async {
    return await _client.rpc('purchase_badge', params: {
      'p_user_id': userId,
      'p_badge_id': badgeId,
    });
  }
}
