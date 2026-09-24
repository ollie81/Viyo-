import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:in_app_purchase/in_app_purchase.dart';
import 'coin_purchase_service.dart';

/// Wraps Google Play Billing (via the in_app_purchase plugin) for
/// Android coin purchases — see buy_coins_screen.dart's module comment
/// for why Android specifically can't sell coins through Stripe/
/// Paystack/Flutterwave/Lemon Squeezy the way the web build does. Not
/// used on web or iOS (this app doesn't currently ship to the App
/// Store; the same StoreKit-backed plugin instance would apply there
/// too if it ever does).
class GooglePlayPurchaseService {
  static final _iap = InAppPurchase.instance;
  static StreamSubscription<List<PurchaseDetails>>? _subscription;

  // The coin package currently being bought, and how to report its
  // result back to whoever called buy(). One at a time only —
  // buy_coins_screen already guards against a second purchase starting
  // before the first resolves, so a single pending slot (rather than a
  // map keyed by product id) is all real usage ever needs.
  static Completer<int>? _pendingCompleter;
  static String? _pendingPackageId;

  /// Call once at app startup (see main.dart) — Flutter's own
  /// in_app_purchase docs warn that a purchase completed while nothing
  /// was subscribed to purchaseStream (e.g. the app was killed
  /// mid-purchase) is only redelivered the next time the app launches,
  /// so this has to be listening from the very start, not just while
  /// BuyCoinsScreen happens to be open.
  static void init() {
    if (kIsWeb) return;
    _subscription ??= _iap.purchaseStream.listen(_onPurchaseUpdate, onError: (_) {});
  }

  static Future<void> _onPurchaseUpdate(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (purchase.status == PurchaseStatus.pending) continue;

      try {
        if (purchase.status == PurchaseStatus.error) {
          _pendingCompleter?.completeError(Exception(purchase.error?.message ?? 'Purchase failed'));
        } else if (purchase.status == PurchaseStatus.canceled) {
          _pendingCompleter?.completeError(Exception('canceled'));
        } else if (purchase.status == PurchaseStatus.purchased ||
            purchase.status == PurchaseStatus.restored) {
          // Falls back to the purchase's own product id when there's
          // no in-flight buy() call waiting — a purchase redelivered
          // on app launch (see init()'s doc comment) still needs to be
          // verified and credited even though nobody's listening for
          // its result right now.
          final packageId = _pendingPackageId ?? purchase.productID;
          final coins = await CoinPurchaseService.verifyGooglePlay(
            packageId: packageId,
            purchaseToken: purchase.verificationData.serverVerificationData,
          );
          _pendingCompleter?.complete(coins);
        }
      } catch (e) {
        _pendingCompleter?.completeError(e);
      } finally {
        if (purchase.pendingCompletePurchase) {
          await _iap.completePurchase(purchase);
        }
        _pendingCompleter = null;
        _pendingPackageId = null;
      }
    }
  }

  /// Starts a Play Billing purchase for [packageId] (must exactly match
  /// a product id configured in Google Play Console — see
  /// google_play_payments.py's module comment) and resolves once the
  /// backend has verified the purchase and credited coins. Throws if
  /// Play Billing isn't available, the product isn't set up in Play
  /// Console yet, or the purchase fails/is canceled.
  static Future<int> buy(String packageId) async {
    if (!await _iap.isAvailable()) {
      throw Exception('Google Play Billing is not available on this device.');
    }
    final response = await _iap.queryProductDetails({packageId});
    if (response.productDetails.isEmpty) {
      throw Exception('This coin package is not set up in Google Play yet.');
    }

    final completer = Completer<int>();
    _pendingCompleter = completer;
    _pendingPackageId = packageId;

    final bool started;
    try {
      started = await _iap.buyConsumable(
        purchaseParam: PurchaseParam(productDetails: response.productDetails.first),
        autoConsume: true,
      );
    } catch (e) {
      _pendingCompleter = null;
      _pendingPackageId = null;
      rethrow;
    }
    if (!started) {
      _pendingCompleter = null;
      _pendingPackageId = null;
      throw Exception('Could not start the Google Play purchase.');
    }

    return completer.future;
  }

  static void dispose() {
    _subscription?.cancel();
    _subscription = null;
  }
}
