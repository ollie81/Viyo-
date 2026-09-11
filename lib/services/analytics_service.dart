import 'supabase_service.dart';

/// First-party product analytics — no third-party SDK/account needed,
/// consistent with this app's existing approach of reusing Supabase
/// directly rather than adding another external dependency (see
/// ModerationService for the same reasoning applied to reports/blocks).
///
/// Revenue and feature-usage events (coin purchases, boosts, spotlight,
/// every AI feature) are already captured server-side in the
/// `transactions` ledger via coins.py — this table only adds the
/// pure-engagement events that never touch the backend at all (posting,
/// liking, following, commenting, signing up), so together the two
/// tables cover the full funnel. See viyo_ai/analytics.py for the
/// admin summary that reads both.
class AnalyticsService {
  static final _client = SupabaseService.client;

  /// Fire-and-forget — analytics must never block or fail the user
  /// action it's attached to.
  static Future<void> track(String event, {Map<String, dynamic>? properties}) async {
    try {
      await _client.from('analytics_events').insert({
        'user_id': SupabaseService.currentUserId,
        'event_name': event,
        'properties': properties ?? {},
      });
    } catch (_) {}
  }
}
