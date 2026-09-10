import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants/supabase_constants.dart';
import '../models/transaction.dart';
import '../models/app_badge.dart';
import 'supabase_service.dart';

/// All coin math happens server-side via Postgres RPCs (see supabase/schema.sql)
/// or, for cross-user transfers (gifting), the Python backend's service-role
/// client (see gift_coins below). The client only ever reads balances/history
/// — it never increments/decrements points_balance directly. This prevents
/// users from editing their own balance by tampering with client requests.
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
    return (data as List)
        .map((e) => CoinTransaction.fromJson(e))
        // free_taste_* rows are internal bookkeeping (see viyo_ai's
        // coins.py) for "did you already use today's free AI action" —
        // always amount 0, never meant to show up as wallet activity.
        .where((t) => !t.type.startsWith('free_taste_'))
        .toList();
  }

  static Future<Map<String, dynamic>> claimDailyCheckin(String userId) async {
    return await _client.rpc('claim_daily_checkin', params: {
      'p_user_id': userId,
    });
  }

  /// Routed through the Python backend's service-role client rather than
  /// the old `gift_coins` Postgres RPC — this app has no way to inspect
  /// that RPC's actual SQL to confirm it correctly credits the *receiver*
  /// (a different user than the caller), and every other cross-user
  /// mutation found this way this session (like_count, comment inserts)
  /// turned out to be silently blocked by Supabase RLS for exactly that
  /// reason. Coins are the core of this app's economy, so gifting — the
  /// one feature that moves them directly between two people — gets the
  /// same "don't trust it, verify or replace" treatment.
  static Future<void> giftCoins({
    required String senderId,
    required String receiverId,
    required int amount,
  }) async {
    final token = _client.auth.currentSession?.accessToken;
    final res = await http.post(
      Uri.parse('${AiBackendConstants.baseUrl}/api/v1/coins/gift'),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'receiver_id': receiverId, 'amount': amount}),
    );
    if (res.statusCode == 200) return;

    String? message;
    try {
      final data = jsonDecode(res.body);
      final detail = data is Map ? data['detail'] : null;
      message = detail is String
          ? detail
          : (detail is Map ? detail['error']?.toString() : null);
    } catch (_) {}
    throw Exception(message ?? 'Gift failed (${res.statusCode})');
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
