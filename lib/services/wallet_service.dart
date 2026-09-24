import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants/supabase_constants.dart';
import 'supabase_service.dart';

/// A creator's earnings from AI Short Drama episode unlocks — kept
/// entirely separate from the general Viyo Coin balance shown on the
/// main wallet screen (see wallet.py's own module doc for why).
class WalletEarnings {
  final int lifetimeCoins;
  final int availableCoins;
  final int pendingWithdrawalCoins;
  final int paidCoins;
  final int minWithdrawalCoins;

  WalletEarnings({
    required this.lifetimeCoins,
    required this.availableCoins,
    required this.pendingWithdrawalCoins,
    required this.paidCoins,
    required this.minWithdrawalCoins,
  });

  factory WalletEarnings.fromJson(Map<String, dynamic> json) => WalletEarnings(
        lifetimeCoins: (json['lifetime_coins'] as num).toInt(),
        availableCoins: (json['available_coins'] as num).toInt(),
        pendingWithdrawalCoins: (json['pending_withdrawal_coins'] as num).toInt(),
        paidCoins: (json['paid_coins'] as num).toInt(),
        minWithdrawalCoins: (json['min_withdrawal_coins'] as num).toInt(),
      );

  static WalletEarnings empty() => WalletEarnings(
        lifetimeCoins: 0,
        availableCoins: 0,
        pendingWithdrawalCoins: 0,
        paidCoins: 0,
        minWithdrawalCoins: 100,
      );
}

class WalletService {
  static Future<Map<String, String>> _headers() async {
    final token = SupabaseService.client.auth.currentSession?.accessToken;
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static Future<WalletEarnings> getEarnings() async {
    final res = await http.get(
      Uri.parse('${AiBackendConstants.baseUrl}/api/v1/wallet/earnings'),
      headers: await _headers(),
    );
    if (res.statusCode != 200) return WalletEarnings.empty();
    return WalletEarnings.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// Requests a withdrawal of the creator's full available balance —
  /// manual for now (a human processes withdrawal_requests outside the
  /// app), so this just records the request and moves the underlying
  /// earnings out of "available" so they can't be requested twice.
  static Future<int> requestWithdrawal() async {
    final res = await http.post(
      Uri.parse('${AiBackendConstants.baseUrl}/api/v1/wallet/withdraw'),
      headers: await _headers(),
    );
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return (data['coins'] as num).toInt();
    }

    String? message;
    try {
      final data = jsonDecode(res.body);
      message = data is Map ? data['detail']?.toString() : null;
    } catch (_) {}
    throw Exception(message ?? 'Could not request withdrawal (${res.statusCode})');
  }
}
