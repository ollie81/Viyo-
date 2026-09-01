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

  /// Creates a browsing-only session with no email/password — lets someone
  /// open the app and look around with zero signup friction. Supabase
  /// issues a real, normally-verified JWT for this session (just with an
  /// `is_anonymous: true` claim), so it works against every existing
  /// authenticated endpoint unchanged; SupabaseService.isGuest is what
  /// the app uses client-side to gate the features that require a real
  /// account. Requires "Allow anonymous sign-ins" enabled in the Supabase
  /// project's Auth settings — throws if it's off.
  static Future<AuthResponse> signInAnonymously() => _client.auth.signInAnonymously();

  /// Adds an email/password to the CURRENT session in place — this is the
  /// "create an account" upgrade path for a guest, not a new signup. Same
  /// user id, same profile row, same coins/posts already on this session:
  /// nothing is lost or re-created, isGuest just flips to false once it
  /// completes. Depending on the project's email-confirmation setting, the
  /// email may need to be confirmed via a link before it fully takes
  /// effect; the password takes effect immediately either way.
  static Future<UserResponse> upgradeToFullAccount({
    required String email,
    required String password,
  }) {
    return _client.auth.updateUser(UserAttributes(email: email, password: password));
  }

  /// Auto-creates a minimal profile for a fresh guest session so the rest
  /// of the app (dashboard, profile screen, etc.) has a profile row to
  /// read immediately — skips the onboarding form entirely, since asking
  /// a guest for a username defeats the point of a no-friction entry.
  /// The username is a throwaway placeholder; upgradeToFullAccount doesn't
  /// touch it; a guest can still change it later from Settings like anyone
  /// else.
  static Future<void> createGuestProfile(String userId) {
    final suffix = userId.replaceAll('-', '').substring(0, 10);
    return createProfile(
      userId: userId,
      username: 'guest_$suffix',
      displayName: 'Guest',
    );
  }

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
  static Future<void> resendConfirmation(String email) async {
  await _client.auth.resend(
    type: OtpType.signup,
    email: email,
  );
}
}


