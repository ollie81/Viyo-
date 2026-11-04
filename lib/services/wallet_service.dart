import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants/supabase_constants.dart';
import 'supabase_service.dart';

/// Where a creator wants to be paid.
class PayoutSettings {
  final String method; // 'paypal' or 'mobile_money'
  final String? paypalEmail;
  final String? momoPhone;
  final String? momoNetwork;
  final String? accountName;
  final String? country;

  const PayoutSettings({
    required this.method,
    this.paypalEmail,
    this.momoPhone,
    this.momoNetwork,
    this.accountName,
    this.country,
  });

  bool get isPaypal => method == 'paypal';

  String get summary => isPaypal
      ? 'PayPal: ${paypalEmail ?? ''}'
      : 'Mobile money (${momoNetwork ?? ''}): ${momoPhone ?? ''}';

  factory PayoutSettings.fromJson(Map<String, dynamic> j) => PayoutSettings(
        method: j['method'] as String? ?? 'paypal',
        paypalEmail: j['paypal_email'] as String?,
        momoPhone: j['momo_phone'] as String?,
        momoNetwork: j['momo_network'] as String?,
        accountName: j['account_name'] as String?,
        country: j['country'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'method': method,
        'paypal_email': paypalEmail,
        'momo_phone': momoPhone,
        'momo_network': momoNetwork,
        'account_name': accountName,
        'country': country,
      };
}

/// A creator's earnings from drama, series and movie unlocks, kept
/// separate from the Viyo Coin balance (see wallet.py). Only coins viewers
/// bought earn cash; values come with their dollar amount.
class WalletEarnings {
  final int lifetimeCoins;
  final int availableCoins;
  final int pendingWithdrawalCoins;
  final int paidCoins;
  final int minWithdrawalCoins;
  final double coinUsd;
  final double minWithdrawalUsd;
  final double availableUsd;
  final double pendingWithdrawalUsd;
  final double paidUsd;
  final PayoutSettings? payoutSettings;
  final double? pendingRequestUsd;
  final String? pendingRequestDestination;

  WalletEarnings({
    required this.lifetimeCoins,
    required this.availableCoins,
    required this.pendingWithdrawalCoins,
    required this.paidCoins,
    required this.minWithdrawalCoins,
    this.coinUsd = 0.006,
    this.minWithdrawalUsd = 10,
    this.availableUsd = 0,
    this.pendingWithdrawalUsd = 0,
    this.paidUsd = 0,
    this.payoutSettings,
    this.pendingRequestUsd,
    this.pendingRequestDestination,
  });

  double get lifetimeUsd => availableUsd + pendingWithdrawalUsd + paidUsd;
  bool get canWithdraw =>
      availableCoins >= minWithdrawalCoins && payoutSettings != null && pendingRequestUsd == null;

  factory WalletEarnings.fromJson(Map<String, dynamic> json) {
    double d(String k, [double fallback = 0]) => (json[k] as num?)?.toDouble() ?? fallback;
    final pending = json['pending_request'] as Map<String, dynamic>?;
    final settings = json['payout_settings'] as Map<String, dynamic>?;
    return WalletEarnings(
      lifetimeCoins: (json['lifetime_coins'] as num).toInt(),
      availableCoins: (json['available_coins'] as num).toInt(),
      pendingWithdrawalCoins: (json['pending_withdrawal_coins'] as num).toInt(),
      paidCoins: (json['paid_coins'] as num).toInt(),
      minWithdrawalCoins: (json['min_withdrawal_coins'] as num).toInt(),
      coinUsd: d('coin_usd', 0.006),
      minWithdrawalUsd: d('min_withdrawal_usd', 10),
      availableUsd: d('available_usd'),
      pendingWithdrawalUsd: d('pending_withdrawal_usd'),
      paidUsd: d('paid_usd'),
      payoutSettings: settings == null ? null : PayoutSettings.fromJson(settings),
      pendingRequestUsd: (pending?['usd_amount'] as num?)?.toDouble(),
      pendingRequestDestination: pending?['payout_destination'] as String?,
    );
  }

  static WalletEarnings empty() => WalletEarnings(
        lifetimeCoins: 0,
        availableCoins: 0,
        pendingWithdrawalCoins: 0,
        paidCoins: 0,
        minWithdrawalCoins: 1667,
      );
}

/// One withdrawal waiting to be paid, as the admin screen shows it.
class AdminWithdrawal {
  final String id;
  final String? username;
  final String? displayName;
  final int coins;
  final double usdAmount;
  final String? payoutDestination;
  final String status;
  final String? createdAt;
  final String? paidAt;

  AdminWithdrawal.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        username = j['username'] as String?,
        displayName = j['display_name'] as String?,
        coins = (j['coins'] as num).toInt(),
        usdAmount = (j['usd_amount'] as num).toDouble(),
        payoutDestination = j['payout_destination'] as String?,
        status = j['status'] as String? ?? 'pending',
        createdAt = j['created_at'] as String?,
        paidAt = j['paid_at'] as String?;
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

  static Never _fail(http.Response res, String fallback) {
    String? message;
    try {
      final data = jsonDecode(res.body);
      message = data is Map ? data['detail']?.toString() : null;
    } catch (_) {}
    throw Exception(message ?? '$fallback (${res.statusCode})');
  }

  static Future<PayoutSettings> savePayoutSettings(PayoutSettings settings) async {
    final res = await http.put(
      Uri.parse('${AiBackendConstants.baseUrl}/api/v1/wallet/payout-settings'),
      headers: await _headers(),
      body: jsonEncode(settings.toJson()),
    );
    if (res.statusCode != 200) _fail(res, 'Could not save payout details');
    return PayoutSettings.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  // ---- admin (X-Admin-Key, same as the other admin screens)

  static Map<String, String> _adminHeaders(String key) => {'Content-Type': 'application/json', 'X-Admin-Key': key};

  static Future<List<AdminWithdrawal>> adminListWithdrawals(String key, {String status = 'pending'}) async {
    final res = await http.get(
      Uri.parse('${AiBackendConstants.baseUrl}/api/v1/admin/withdrawals?status=$status'),
      headers: _adminHeaders(key),
    );
    if (res.statusCode != 200) _fail(res, 'Could not load withdrawals');
    return (jsonDecode(res.body) as List).map((e) => AdminWithdrawal.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<void> adminSettle(String key, String id, {required bool paid, String? note}) async {
    final res = await http.post(
      Uri.parse('${AiBackendConstants.baseUrl}/api/v1/admin/withdrawals/$id/${paid ? 'paid' : 'reject'}'),
      headers: _adminHeaders(key),
      body: jsonEncode({'note': note}),
    );
    if (res.statusCode != 200) _fail(res, 'Could not update withdrawal');
  }

  /// Requests a withdrawal of the creator's full available balance —
  /// manual for now (a human processes withdrawal_requests outside the
  /// app), so this just records the request and moves the underlying
  /// earnings out of "available" so they can't be requested twice.
  /// Returns the dollar amount requested.
  static Future<double> requestWithdrawal() async {
    final res = await http.post(
      Uri.parse('${AiBackendConstants.baseUrl}/api/v1/wallet/withdraw'),
      headers: await _headers(),
    );
    if (res.statusCode != 200) _fail(res, 'Could not request withdrawal');
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return (data['usd_amount'] as num?)?.toDouble() ?? 0;
  }
}
