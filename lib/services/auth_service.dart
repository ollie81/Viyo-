import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';

class AuthService {
  static final _client = SupabaseService.client;

  static Future<AuthResponse> signUp({
    required String email,
    required String password,
  }) {
    return _client.auth.signUp(email: email, password: password);
  }

  static Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) {
    return _client.auth.signInWithPassword(email: email, password: password);
  }

  static Future<void> signOut() => _client.auth.signOut();

  /// Call once, right after sign up, during onboarding.
  static Future<void> createProfile({
    required String userId,
    required String username,
    required String displayName,
    String? referredByCode,
  }) async {
    String? referrerId;
    if (referredByCode != null && referredByCode.trim().isNotEmpty) {
      final referrer = await _client
          .from('profiles')
          .select('id')
          .eq('referral_code', referredByCode.trim())
          .maybeSingle();
      referrerId = referrer?['id'];
    }

    await _client.from('profiles').insert({
      'id': userId,
      'username': username,
      'display_name': displayName,
      if (referrerId != null) 'referred_by': referrerId,
    });

    // Award referral bonus to both sides via a transaction row + balance bump.
    // In production this should be a single RPC (see schema.sql pattern) to
    // avoid partial failures; kept simple here for clarity.
    if (referrerId != null) {
      await _client.rpc('grant_referral_bonus', params: {
        'p_new_user_id': userId,
        'p_referrer_id': referrerId,
      });
    }
  }

  static Future<bool> isUsernameAvailable(String username) async {
    final existing = await _client
        .from('profiles')
        .select('id')
        .eq('username', username)
        .maybeSingle();
    return existing == null;
  }
}

