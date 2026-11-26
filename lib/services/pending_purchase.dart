import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// A NardoPay checkout the viewer left VIYO for. On the web, NardoPay's page opens in the SAME tab (a new tab opened
/// after a network request is blocked by phone browsers), so VIYO remembers the purchase here and picks it back up
/// when NardoPay sends the viewer back to viyo.site/app. This only remembers WHICH order to check: whether it was
/// paid is always asked from the server, which knows only after NardoPay's signed confirmation.
class PendingPurchase {
  final String kind; // premium | coins | donation | campaign
  final String id; // subscription id or coin order id
  final DateTime savedAt;

  const PendingPurchase(this.kind, this.id, this.savedAt);

  static const _key = 'pending_nardopay_purchase';

  /// How long after leaving for NardoPay a return still resumes the check.
  static const maxAge = Duration(hours: 2);

  static Future<void> save(String kind, String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, '$kind|$id|${DateTime.now().toUtc().toIso8601String()}');
    } catch (_) {}
  }

  /// The pending purchase, if one was saved recently enough (an old one is cleared).
  static Future<PendingPurchase?> peek() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return null;
      final parts = raw.split('|');
      final at = parts.length == 3 ? DateTime.tryParse(parts[2]) : null;
      if (at == null || !const {'premium', 'coins', 'donation', 'campaign'}.contains(parts[0]) || parts[1].isEmpty ||
          DateTime.now().toUtc().difference(at) > maxAge) {
        await prefs.remove(_key);
        return null;
      }
      return PendingPurchase(parts[0], parts[1], at);
    } catch (_) {
      return null;
    }
  }

  /// The pending purchase of this kind, if any.
  static Future<PendingPurchase?> peekKind(String kind) async {
    final p = await peek();
    return p != null && p.kind == kind ? p : null;
  }

  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {}
  }
}

/// Opens a checkout page: in the same tab on the web (never blocked), externally elsewhere.
Future<bool> openCheckoutPage(String url) {
  final uri = Uri.parse(url);
  if (kIsWeb) return launchUrl(uri, webOnlyWindowName: '_self');
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}
