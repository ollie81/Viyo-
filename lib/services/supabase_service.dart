import 'package:supabase_flutter/supabase_flutter.dart';
import '../constants/supabase_constants.dart';

/// Thin wrapper so the rest of the app never imports supabase_flutter
/// directly — makes it easy to swap/mocking in tests.
class SupabaseService {
  static Future<void> init() async {
    await Supabase.initialize(
      url: SupabaseConstants.url,
      anonKey: SupabaseConstants.anonKey,
    );
  }

  static SupabaseClient get client => Supabase.instance.client;

  static User? get currentUser => client.auth.currentUser;

  static String? get currentUserId => client.auth.currentUser?.id;

  static bool get isLoggedIn => currentUser != null;
}
