import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../constants/supabase_constants.dart';
import '../models/post.dart';
import '../models/series.dart';
import '../services/adsense_stub.dart' if (dart.library.html) '../services/adsense_web.dart' as adsense;
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';

/// Whether web ads are switched on (GET /api/v1/web-ads/config, off until AdSense has approved viyo.site) and the
/// viewer isn't a Premium member. Asked once per app start.
class WebAdsConfig {
  final bool enabled;
  final String? client, slot;
  // Optional extra AdSense units: in-feed (native, needs its layout key) and multiplex (recommendations).
  final String? infeedSlot, infeedLayoutKey, multiplexSlot;
  const WebAdsConfig(
      {required this.enabled, this.client, this.slot, this.infeedSlot, this.infeedLayoutKey, this.multiplexSlot});
  static const off = WebAdsConfig(enabled: false);

  factory WebAdsConfig.fromJson(Map j) => WebAdsConfig(
        enabled: j['enabled'] == true && j['client'] is String && j['slot'] is String,
        client: j['client'] as String?,
        slot: j['slot'] as String?,
        infeedSlot: j['infeed_slot'] as String?,
        infeedLayoutKey: j['infeed_layout_key'] as String?,
        multiplexSlot: j['multiplex_slot'] as String?,
      );

  static Future<WebAdsConfig>? _cached;

  /// For tests.
  static Future<WebAdsConfig> Function()? override;

  static Future<WebAdsConfig> get() {
    final o = override;
    if (o != null) return o();
    if (!kIsWeb) return Future.value(off);
    return _cached ??= _load();
  }

  static Future<WebAdsConfig> _load() async {
    try {
      final res = await http
          .get(Uri.parse('${AiBackendConstants.baseUrl}/api/v1/web-ads/config'))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return off;
      final cfg = WebAdsConfig.fromJson(jsonDecode(res.body) as Map);
      if (!cfg.enabled) return off;
      if (await _isPremium()) return off;                 // Premium members see no ads
      return cfg;
    } catch (_) {
      return off;
    }
  }

  static Future<bool> _isPremium() async {
    final uid = SupabaseService.currentUserId;
    if (uid == null) return false;
    try {
      final row = await SupabaseService.client.from('profiles').select('is_subscribed').eq('id', uid).maybeSingle();
      return row != null && row['is_subscribed'] == true;
    } catch (_) {
      return true;                                         // unsure: don't risk showing ads to a member
    }
  }
}

/// Which content may carry a web ad (beside it, never over the video). Premium members are handled by WebAdsConfig
/// (they get no ads at all). Rules agreed with the owner:
///   * free content only: free episodes (the first kFreeEpisodeCount, or ones the creator made free) and free videos;
///   * never on content the viewer paid for (coins or ad tickets), never on a series the viewer has paid episodes in;
///   * never on the viewer's own content;
///   * never on payment screens (checkout, wallet, Premium, coins, donate, campaigns, Studio credits): see
///     [noAdScreenFiles], which a test enforces.
class AdEligibility {
  const AdEligibility._();

  /// Screens that must never show an ad (lib/screens/...). A test fails if one of them uses WebAdCard.
  static const noAdScreenFiles = [
    'wallet_screen.dart',
    'wallet/buy_coins_screen.dart',
    'wallet/subscribe_screen.dart',
    'wallet/donate_screen.dart',
    'creator/brand_campaigns_screen.dart',
    'creator/brand_deals_screen.dart',
    'admin/studio_credits_admin_screen.dart',
    'store_screen.dart',
  ];

  static bool _paidEpisode(Post p) {
    if (!p.isEpisode || !p.unlockedByMe) return false;
    if (p.isFree != null) return !p.isFree!;
    return (p.episodeNumber ?? 1) > kFreeEpisodeCount;
  }

  /// A single post or episode the viewer is looking at.
  static bool forContent(Post post, {required String? viewerId}) {
    if (viewerId != null && post.userId == viewerId) return false;
    if (!post.isEpisode) return true;                          // creator videos and posts are free to watch
    if (_paidEpisode(post)) return false;                      // they paid for it: no ads
    if (post.isFree != null) return post.isFree!;
    return (post.episodeNumber ?? 1) <= kFreeEpisodeCount;     // free episodes only (a locked one isn't watched)
  }

  /// A drama or movie page: no ads for its creator or for anyone who paid for any of its episodes.
  static bool forSeries({required String seriesOwnerId, required List<Post> episodes, required String? viewerId}) {
    if (viewerId != null && seriesOwnerId == viewerId) return false;
    return !episodes.any(_paidEpisode);
  }
}

/// What kind of AdSense unit a placement uses. Display ads are images/banners, never video ads.
enum WebAdKind {
  display, // the responsive display unit
  infeed, // a native card between content cards (falls back to display until the in-feed unit is set up)
  multiplex, // a grid of recommended-content ads (shown only once the multiplex unit is set up)
}

/// Where the ad sits: in the page's column, or in a side rail next to the video on wide screens.
enum WebAdSize { inline, rail }

/// Sizes that fit the space, so ads never crowd content on a phone or float in empty space on a desktop.
class WebAdLayout {
  const WebAdLayout._();
  static const maxInlineWidth = 970.0; // never wider than a large leaderboard
  static const railWidth = 336.0;
  static const railMinScreen = 1100.0; // a side rail only when the screen is this wide

  static double height(WebAdKind kind, WebAdSize size, double width) {
    if (size == WebAdSize.rail) return 600;               // a 300x600 half-page next to the video
    return switch (kind) {
      WebAdKind.display => width < 600 ? 280 : (width < 1000 ? 250 : 200),
      WebAdKind.infeed => width < 600 ? 300 : 260,
      WebAdKind.multiplex => width < 600 ? 520 : (width < 1000 ? 420 : 380),
    };
  }
}

/// A clearly labelled responsive display ad (Google AdSense) for the web app, placed between content: never over a
/// video or its controls. Shows nothing at all when ads are off, on Android/iOS, for Premium members, when an ad
/// blocker stops the script, or when Google has no ad to show.
class WebAdCard extends StatefulWidget {
  /// One placement = one ad element per page load (e.g. 'discover', 'profile', 'series').
  final String placement;
  final EdgeInsetsGeometry margin;
  final WebAdKind kind;
  final WebAdSize size;
  /// Called once if the ad won't show (ads off, blocked, no ad), so a screen can give the space back.
  final VoidCallback? onHidden;
  const WebAdCard({
    super.key,
    required this.placement,
    this.margin = const EdgeInsets.symmetric(vertical: 12),
    this.kind = WebAdKind.display,
    this.size = WebAdSize.inline,
    this.onHidden,
  });

  @override
  State<WebAdCard> createState() => _WebAdCardState();
}

class _WebAdCardState extends State<WebAdCard> {
  String? _viewType;
  bool _hidden = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    if (!adsense.adsenseSupported) return;
    final cfg = await WebAdsConfig.get();
    if (!mounted || !cfg.enabled) return _hide();
    final (slot, format, layoutKey) = switch (widget.kind) {
      WebAdKind.infeed when cfg.infeedSlot != null => (cfg.infeedSlot!, 'fluid', cfg.infeedLayoutKey),
      WebAdKind.multiplex => (cfg.multiplexSlot, 'autorelaxed', null),
      _ => (cfg.slot!, 'auto', null),
    };
    if (slot == null) return _hide();                      // that unit isn't set up yet
    final status = adsense.adSlotStatus(widget.placement);
    if (status == 'unfilled') return _hide();
    if (!await adsense.loadAdsense(cfg.client!)) return _hide();   // ad blocker or network: hide quietly
    if (!mounted) return;
    setState(() => _viewType = adsense.registerAdSlot(
        placement: widget.placement, client: cfg.client!, slot: slot, format: format, layoutKey: layoutKey));
    var checks = 0;
    _poll = Timer.periodic(const Duration(seconds: 1), (t) {
      final s = adsense.adSlotStatus(widget.placement);
      checks++;
      if (s == 'filled') {
        t.cancel();
      } else if (s == 'unfilled' || checks >= 15) {
        t.cancel();
        if (s != 'filled') _hide();
      }
    });
  }

  void _hide() {
    if (!mounted || _hidden) return;
    setState(() => _hidden = true);
    widget.onHidden?.call();
  }

  @override
  Widget build(BuildContext context) {
    final vt = _viewType;
    if (vt == null || _hidden) return const SizedBox.shrink();
    return Padding(
      padding: widget.margin,
      child: LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth.isFinite ? c.maxWidth : MediaQuery.sizeOf(context).width;
        final width = widget.size == WebAdSize.inline && w > WebAdLayout.maxInlineWidth ? WebAdLayout.maxInlineWidth : w;
        return Center(
          child: SizedBox(
            width: width,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              const Padding(
                padding: EdgeInsets.only(left: 2, bottom: 4),
                child: Text('Advertisement',
                    style: TextStyle(fontSize: 10.5, color: AppColors.textMuted, letterSpacing: 0.3)),
              ),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  color: AppColors.surface,
                  width: width,
                  height: WebAdLayout.height(widget.kind, widget.size, w),
                  child: HtmlElementView(viewType: vt),
                ),
              ),
            ]),
          ),
        );
      }),
    );
  }
}
