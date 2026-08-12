/// Formats a coin amount: whole numbers show clean ("15"), fractional
/// amounts show up to 2 decimals ("0.05") — used anywhere a reward
/// amount is interpolated directly into a message/toast.
String formatCoins(num amount) {
  final d = amount.toDouble();
  if (d == d.roundToDouble()) return d.toStringAsFixed(0);
  return d.toStringAsFixed(2);
}
