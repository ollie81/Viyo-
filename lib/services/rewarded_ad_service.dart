import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'coin_service.dart';

/// Rewarded video ads that credit Viyo Coins — the "watch an ad for
/// coins" option offered from the wallet and the insufficient-coins
/// sheet.
///
/// Uses RewardedInterstitialAd rather than plain RewardedAd: Viyo's
/// AdMob account has a "Rewarded Interstitial" ad unit created for
/// this app, not a plain "Rewarded" one (the two are different ad
/// unit formats that each need their own matching SDK class — a
/// Rewarded Interstitial ad unit id fails to load through
/// RewardedAd.load). The two classes' load/show API is otherwise
/// identical, including onUserEarnedReward, so nothing else about this
/// service's own behavior changes — this still only ever shows when
/// the viewer explicitly taps "Watch Ad", same as a plain rewarded ad.
///
/// The Android ad unit id below is Viyo's real one; the iOS id is
/// still Google's public TEST id (always serves a test creative, never
/// a real ad) since Viyo doesn't have an iOS AdMob app set up yet —
/// swap it in once one exists, following the same steps used for
/// Android.
///
/// google_mobile_ads has no web implementation, and Platform.isIOS
/// below (dart:io) throws outright on web — every public method here
/// checks kIsWeb first and no-ops, so this service is safe to call
/// from shared (mobile + web) screens like the wallet or the
/// insufficient-coins sheet without a platform check at each call site.
class RewardedAdService {
  static const _androidUnitId = 'ca-app-pub-4006935524883605/4402469307';
  static const _testIosUnitId = 'ca-app-pub-3940256099942544/1712485313';

  static String get _adUnitId => Platform.isIOS ? _testIosUnitId : _androidUnitId;

  static RewardedInterstitialAd? _preloaded;
  static bool _loading = false;

  /// Preloads the next ad so tapping "Watch Ad" doesn't have to wait on
  /// a network round-trip first. Safe to call anytime (app start, and
  /// again after each watch) — silently no-ops if a load is already in
  /// flight or one's already sitting ready; showAndClaim() falls back
  /// to an on-demand load if this never succeeded.
  static void preload() {
    if (kIsWeb || _preloaded != null || _loading) return;
    _loading = true;
    RewardedInterstitialAd.load(
      adUnitId: _adUnitId,
      request: const AdRequest(),
      rewardedInterstitialAdLoadCallback: RewardedInterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _preloaded = ad;
          _loading = false;
        },
        onAdFailedToLoad: (error) {
          _loading = false;
        },
      ),
    );
  }

  /// Shows a rewarded ad and, only if the viewer actually watches it
  /// through to the reward point (the SDK calls onUserEarnedReward —
  /// closing early never fires it), claims the coin reward from the
  /// backend. The backend is what actually credits the balance and
  /// enforces the daily cap (see viyo_ai's rewarded_ads.py) — this
  /// method never assumes the claim succeeded just because the ad played.
  ///
  /// Returns the coins earned, or null if no ad was available, the
  /// viewer closed it before earning the reward, or the backend claim
  /// failed (e.g. today's daily cap already hit).
  static Future<int?> showAndClaim() async {
    if (kIsWeb) return null;
    var ad = _preloaded;
    _preloaded = null;
    ad ??= await _loadNow();
    if (ad == null) return null;

    final dismissed = Completer<void>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        if (!dismissed.isCompleted) dismissed.complete();
        preload();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        if (!dismissed.isCompleted) dismissed.complete();
        preload();
      },
    );

    var earned = false;
    await ad.show(onUserEarnedReward: (ad, reward) => earned = true);
    await dismissed.future;
    if (!earned) return null;

    try {
      return await CoinService.claimRewardedAd();
    } catch (_) {
      return null;
    }
  }

  static Future<RewardedInterstitialAd?> _loadNow() async {
    final completer = Completer<RewardedInterstitialAd?>();
    RewardedInterstitialAd.load(
      adUnitId: _adUnitId,
      request: const AdRequest(),
      rewardedInterstitialAdLoadCallback: RewardedInterstitialAdLoadCallback(
        onAdLoaded: (ad) => completer.complete(ad),
        onAdFailedToLoad: (error) => completer.complete(null),
      ),
    );
    return completer.future;
  }
}
