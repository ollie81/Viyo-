import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Interstitial ads shown occasionally between episodes in the video
/// feed (see VideoFeedScreen's _onPageChanged) for viewers who never
/// buy coins or subscribe — unlike RewardedAdService, this is never
/// opt-in and pays out nothing, so it's shown sparingly (every few
/// swipes) rather than on every episode change.
///
/// The Android ad unit id below is Viyo's real one; the iOS id is
/// still Google's public TEST id since Viyo doesn't have an iOS AdMob
/// app set up yet — same swap-before-release rule as
/// RewardedAdService's own module comment: never mix test and real ids
/// for the same platform.
///
/// google_mobile_ads has no web implementation, and Platform.isIOS
/// below (dart:io) throws outright on web — every public method here
/// checks kIsWeb first and no-ops, same guard RewardedAdService uses.
class InterstitialAdService {
  static const _androidUnitId = 'ca-app-pub-4006935524883605/2095125302';
  static const _testIosUnitId = 'ca-app-pub-3940256099942544/4411468910';

  static String get _adUnitId => Platform.isIOS ? _testIosUnitId : _androidUnitId;

  static InterstitialAd? _preloaded;
  static bool _loading = false;

  /// Preloads the next ad so showIfReady() never has to wait on a
  /// network round-trip — safe to call anytime; no-ops if a load is
  /// already in flight or one's already sitting ready.
  static void preload() {
    if (kIsWeb || _preloaded != null || _loading) return;
    _loading = true;
    InterstitialAd.load(
      adUnitId: _adUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
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

  /// Shows the preloaded ad if one is ready, otherwise does nothing —
  /// deliberately never waits on a fresh load (unlike RewardedAdService's
  /// showAndClaim), since this fires mid-scroll and a loading delay
  /// here would stall the feed instead of just skipping that one ad.
  /// Returns whether an ad was actually shown.
  static Future<bool> showIfReady() async {
    if (kIsWeb) return false;
    final ad = _preloaded;
    if (ad == null) {
      preload();
      return false;
    }
    _preloaded = null;

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        preload();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        preload();
      },
    );
    await ad.show();
    return true;
  }
}
