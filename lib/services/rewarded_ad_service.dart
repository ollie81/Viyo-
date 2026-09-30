import 'dart:async';
import 'dart:io';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'coin_service.dart';

/// Rewarded video ads that credit Viyo Coins — the "watch an ad for
/// coins" option offered from the wallet and the insufficient-coins
/// sheet.
///
/// The ad unit ids below are Google's own public TEST ids: they always
/// fill with a test creative and never show (or pay out for) a real
/// ad. Swap these for this app's real AdMob rewarded ad unit ids
/// before a store release — shipping test ids to production risks the
/// AdMob account, and shipping real ids into this sandbox risks
/// invalid-traffic flags, so the two must never be mixed.
class RewardedAdService {
  static const _testAndroidUnitId = 'ca-app-pub-3940256099942544/5224354917';
  static const _testIosUnitId = 'ca-app-pub-3940256099942544/1712485313';

  static String get _adUnitId => Platform.isIOS ? _testIosUnitId : _testAndroidUnitId;

  static RewardedAd? _preloaded;
  static bool _loading = false;

  /// Preloads the next ad so tapping "Watch Ad" doesn't have to wait on
  /// a network round-trip first. Safe to call anytime (app start, and
  /// again after each watch) — silently no-ops if a load is already in
  /// flight or one's already sitting ready; showAndClaim() falls back
  /// to an on-demand load if this never succeeded.
  static void preload() {
    if (_preloaded != null || _loading) return;
    _loading = true;
    RewardedAd.load(
      adUnitId: _adUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
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

  static Future<RewardedAd?> _loadNow() async {
    final completer = Completer<RewardedAd?>();
    RewardedAd.load(
      adUnitId: _adUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) => completer.complete(ad),
        onAdFailedToLoad: (error) => completer.complete(null),
      ),
    );
    return completer.future;
  }
}
