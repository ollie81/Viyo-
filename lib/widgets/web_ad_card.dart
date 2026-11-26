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
  const WebAdsConfig({required this.enabled, this.client, this.slot});
  static const off = WebAdsConfig(enabled: false);

  factory WebAdsConfig.fromJson(Map j) => WebAdsConfig(
        enabled: j['enabled'] == true && j['client'] is String && j['slot'] is String,
        client: j['client'] as String?,
        slot: j['slot'] as String?,
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

/// A clearly labelled responsive display ad (Google AdSense) for the web app, placed between content: never over a
/// video or its controls. Shows nothing at all when ads are off, on Android/iOS, for Premium members, when an ad
/// blocker stops the script, or when Google has no ad to show.
class WebAdCard extends StatefulWidget {
  /// One placement = one ad element per page load (e.g. 'discover', 'profile', 'series').
  final String placement;
  final EdgeInsetsGeometry margin;
  const WebAdCard({super.key, required this.placement, this.margin = const EdgeInsets.symmetric(vertical: 12)});

  static const height = 280.0;

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
    if (!mounted || !cfg.enabled) return;
    final status = adsense.adSlotStatus(widget.placement);
    if (status == 'unfilled') return setState(() => _hidden = true);
    if (!await adsense.loadAdsense(cfg.client!)) {
      if (mounted) setState(() => _hidden = true);         // ad blocker or network: hide quietly
      return;
    }
    if (!mounted) return;
    setState(() => _viewType = adsense.registerAdSlot(placement: widget.placement, client: cfg.client!, slot: cfg.slot!));
    var checks = 0;
    _poll = Timer.periodic(const Duration(seconds: 1), (t) {
      final s = adsense.adSlotStatus(widget.placement);
      checks++;
      if (s == 'filled') {
        t.cancel();
      } else if (s == 'unfilled' || checks >= 15) {
        t.cancel();
        if (mounted && s != 'filled') setState(() => _hidden = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final vt = _viewType;
    if (vt == null || _hidden) return const SizedBox.shrink();
    return Padding(
      padding: widget.margin,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        const Padding(
          padding: EdgeInsets.only(left: 2, bottom: 4),
          child: Text('Advertisement', style: TextStyle(fontSize: 10.5, color: AppColors.textMuted, letterSpacing: 0.3)),
        ),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Container(
            color: AppColors.surface,
            height: WebAdCard.height,
            width: double.infinity,
            child: HtmlElementView(viewType: vt),
          ),
        ),
      ]),
    );
  }
}
