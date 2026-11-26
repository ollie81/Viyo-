import 'package:flutter_test/flutter_test.dart';
import 'package:viyo/services/wallet_service.dart';

void main() {
  test('held earnings are read separately and count in the lifetime total', () {
    final e = WalletEarnings.fromJson({
      'lifetime_coins': 150,
      'available_coins': 50,
      'pending_withdrawal_coins': 0,
      'paid_coins': 0,
      'min_withdrawal_coins': 1667,
      'available_usd': 0.30,
      'held_coins': 100,
      'held_usd': 0.60,
      'next_available_at': '2026-12-10T12:00:00Z',
      'hold_days': 14,
    });
    expect(e.heldCoins, 100);
    expect(e.heldUsd, 0.60);
    expect(e.nextAvailableAt, '2026-12-10T12:00:00Z');
    expect(e.lifetimeUsd, closeTo(0.90, 0.001));
    expect(e.canWithdraw, isFalse); // held coins never count toward the minimum
  });

  test('an older server answer without held fields still works', () {
    final e = WalletEarnings.fromJson({
      'lifetime_coins': 10, 'available_coins': 10, 'pending_withdrawal_coins': 0, 'paid_coins': 0,
      'min_withdrawal_coins': 1667,
    });
    expect(e.heldCoins, 0);
    expect(e.holdDays, 14);
  });
}
