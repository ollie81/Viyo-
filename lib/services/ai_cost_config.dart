/// Centralized AI operation costs in Viyo Coins.
///
/// All screens read costs from here — never hardcode numbers in UI files.
/// This lets the business adjust prices in one place without touching
/// every screen.
///
/// IMPORTANT: these values are UI-only display costs. The actual deduction
/// must be performed by a server-side Supabase RPC (e.g. `deduct_coins_for_ai`)
/// that checks the user's balance and deducts atomically. The client must
/// never directly decrement `points_balance` — that can be bypassed.
///
/// Required backend RPC (not yet implemented — see migration notes):
///   deduct_coins_for_ai(p_user_id uuid, p_operation text, p_cost numeric)
///   → { success: bool, new_balance: numeric, message: text }
class AiCostConfig {
  AiCostConfig._();

  // ── AI feature costs (Viyo Coins) ──────────────────────────────────────
  static const double aiCoach = 20.0;
  static const double aiCaptions = 10.0;
  static const double aiHighlights = 25.0;
  static const double aiRepurpose = 30.0;
  static const double aiEdit = 50.0;
  static const double postBoost = 50.0;
  static const double improveCaption = 5.0;

  // ── Display helpers ────────────────────────────────────────────────────

  /// Short human-readable cost string: "20 Coins", "5 Coins"
  static String label(double cost) {
    final n = cost % 1 == 0 ? cost.toInt().toString() : cost.toStringAsFixed(1);
    return '$n Coins';
  }

  /// Returns true if the user's balance is sufficient for this operation.
  /// Call this before showing the confirmation dialog, not as a substitute
  /// for the server-side check.
  static bool canAfford(double balance, double cost) => balance >= cost;
}
