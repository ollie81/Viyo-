/// Thrown by AiService methods when the backend returns 402 for a
/// coin-gated AI feature — carries exactly what the "not enough coins"
/// sheet needs to show, straight from the server (the single source of
/// truth for balance/cost, never computed client-side).
class InsufficientCoinsException implements Exception {
  final String feature;
  final int balance;
  final int needed;

  InsufficientCoinsException({
    required this.feature,
    required this.balance,
    required this.needed,
  });

  @override
  String toString() => 'Not enough coins for $feature (have $balance, need $needed)';
}

/// Coin cost per gated AI feature — must stay in sync with
/// viyo_ai/coins.py's FEATURE_COSTS. Used only to show the cost chip
/// on buttons before tapping; the backend is always the source of
/// truth for what's actually charged.
class FeatureCoinCosts {
  static const hookCheck = 5;
  static const captionVariants = 5;
  static const improveCaption = 5;
  static const coachMessage = 10;
  static const repurpose = 40;
}
