/// Off the web (Android, iOS, tests) there is no AdSense: every call does nothing.
library;

bool get adsenseSupported => false;

/// Loads Google's AdSense script once. Returns whether it loaded.
Future<bool> loadAdsense(String client) async => false;

/// The view type of a registered ad slot for [placement], or null when not on the web.
String? registerAdSlot({required String placement, required String client, required String slot}) => null;

/// 'filled' | 'unfilled' | 'blocked' | 'pending' for [placement].
String adSlotStatus(String placement) => 'blocked';
