import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../constants/supabase_constants.dart';
import 'push_notification_service.dart';
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

  /// Unregisters this device's push token first, while the session
  /// that owns it (RLS: auth.uid() = user_id) is still valid — doing
  /// it after signOut() would just fail silently, leaving the next
  /// person who signs in on this device receiving the previous user's
  /// pushes until they happen to re-register.
  static Future<void> signOut() async {
    await PushNotificationService.unregister();
    await _client.auth.signOut();
  }

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
  ///
  /// Referral attribution (referral_code/referred_by columns, the
  /// bonus-granting call) is optional best-effort — every step of it
  /// is wrapped so a schema piece that isn't migrated yet degrades to
  /// "no referral credit" rather than failing account creation itself.
  /// Entering something in an optional referral-code field must never
  /// be able to leave someone signed up with no profile row.
  static Future<void> createProfile({
    required String userId,
    required String username,
    required String displayName,
    String? referredByCode,
  }) async {
    String? referrerId;
    if (referredByCode != null && referredByCode.trim().isNotEmpty) {
      try {
        final referrer = await _client
            .from('profiles')
            .select('id')
            .eq('referral_code', referredByCode.trim())
            .maybeSingle();
        referrerId = referrer?['id'];
      } catch (_) {
        // referral_code column not migrated yet, or the code didn't
        // resolve — proceed with a normal, unattributed signup.
      }
    }

    // Every profile gets a shareable referral code, deterministically
    // derived from its own id (see UserProfile.fromJson's matching
    // fallback and invite_screen.dart) — no separate generation or
    // uniqueness-retry step needed; profiles.referral_code's own
    // UNIQUE constraint is the actual backstop once migrated.
    final referralCode = userId.replaceAll('-', '').substring(0, 8).toUpperCase();

    final baseProfileData = {
      'id': userId,
      'username': username,
      'display_name': displayName,
    };
    try {
      await _client.from('profiles').insert({
        ...baseProfileData,
        'referral_code': referralCode,
        if (referrerId != null) 'referred_by': referrerId,
      });
    } catch (e) {
      // referral_code/referred_by not migrated yet — retry with just
      // the fields every version of this table has always had, rather
      // than lose account creation over optional referral metadata.
      await _client.from('profiles').insert(baseProfileData);
      referrerId = null;
    }

    if (referrerId != null) {
      try {
        final token = _client.auth.currentSession?.accessToken;
        await http.post(
          Uri.parse('${AiBackendConstants.baseUrl}/api/v1/referrals/grant-bonus'),
          headers: {
            'Content-Type': 'application/json',
            if (token != null) 'Authorization': 'Bearer $token',
          },
          body: jsonEncode({'referrer_id': referrerId}),
        );
      } catch (_) {
        // Bonus endpoint not reachable, or already granted — the
        // profile itself is already created successfully by this
        // point, so this must never surface as a failed signup.
      }
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


