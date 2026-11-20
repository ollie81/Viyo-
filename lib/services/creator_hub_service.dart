import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../constants/supabase_constants.dart';

class HubProduction {
  final String kind; // series | video
  final String id;
  final String title;
  final String? coverUrl;
  final String contentType;
  final int episodes, publicEpisodes, coinPrice, views, likes, comments, shares, earnedCoins;
  final bool earns;
  HubProduction({required this.kind, required this.id, required this.title, this.coverUrl, required this.contentType,
      required this.episodes, required this.publicEpisodes, required this.coinPrice, required this.views,
      required this.likes, required this.comments, required this.shares, required this.earnedCoins, required this.earns});
  factory HubProduction.fromJson(Map j) => HubProduction(
        kind: (j['kind'] ?? 'video').toString(),
        id: j['id'].toString(),
        title: (j['title'] ?? '').toString(),
        coverUrl: j['cover_url'] as String?,
        contentType: (j['content_type'] ?? '').toString(),
        episodes: (j['episodes'] as num?)?.toInt() ?? 0,
        publicEpisodes: (j['public_episodes'] as num?)?.toInt() ?? 0,
        coinPrice: (j['coin_price'] as num?)?.toInt() ?? 0,
        views: (j['views'] as num?)?.toInt() ?? 0,
        likes: (j['likes'] as num?)?.toInt() ?? 0,
        comments: (j['comments'] as num?)?.toInt() ?? 0,
        shares: (j['shares'] as num?)?.toInt() ?? 0,
        earnedCoins: (j['earned_coins'] as num?)?.toInt() ?? 0,
        earns: j['earns'] == true,
      );
}

class CreatorHub {
  final int views, likes, comments, shares;
  final int? followers;
  final int lifetimeCoins, availableCoins, pendingCoins, paidCoins, last30Coins;
  final double lifetimeUsd, availableUsd, paidUsd;
  final bool canWithdraw, payoutDetailsSaved, withdrawalPending;
  final List<HubProduction> productions;
  final List<({String title, String detail})> earns;
  final List<String> doesNotEarn;
  final String payoutDetail;
  final String note;
  CreatorHub({required this.views, required this.likes, required this.comments, required this.shares, this.followers,
      required this.lifetimeCoins, required this.availableCoins, required this.pendingCoins, required this.paidCoins,
      required this.last30Coins, required this.lifetimeUsd, required this.availableUsd, required this.paidUsd,
      required this.canWithdraw, required this.payoutDetailsSaved, required this.withdrawalPending,
      required this.productions, required this.earns, required this.doesNotEarn, required this.payoutDetail,
      required this.note});

  factory CreatorHub.fromJson(Map<String, dynamic> j) {
    final a = (j['audience'] as Map?) ?? const {};
    final e = (j['earnings'] as Map?) ?? const {};
    final h = (j['how_you_earn'] as Map?) ?? const {};
    int i(Map m, String k) => (m[k] as num?)?.toInt() ?? 0;
    double d(Map m, String k) => (m[k] as num?)?.toDouble() ?? 0;
    return CreatorHub(
      views: i(a, 'views'), likes: i(a, 'likes'), comments: i(a, 'comments'), shares: i(a, 'shares'),
      followers: (a['followers'] as num?)?.toInt(),
      lifetimeCoins: i(e, 'lifetime_coins'), availableCoins: i(e, 'available_coins'), pendingCoins: i(e, 'pending_coins'),
      paidCoins: i(e, 'paid_coins'), last30Coins: i(e, 'last_30_days_coins'),
      lifetimeUsd: d(e, 'lifetime_usd'), availableUsd: d(e, 'available_usd'), paidUsd: d(e, 'paid_usd'),
      canWithdraw: e['can_withdraw'] == true, payoutDetailsSaved: e['payout_details_saved'] == true,
      withdrawalPending: e['withdrawal_pending'] == true,
      productions: [for (final p in (j['productions'] as List? ?? const [])) HubProduction.fromJson(p as Map)],
      earns: [
        for (final x in (h['earns'] as List? ?? const []))
          (title: ((x as Map)['title'] ?? '').toString(), detail: (x['detail'] ?? '').toString()),
      ],
      doesNotEarn: ((h['does_not_earn'] as List?) ?? []).map((e) => e.toString()).toList(),
      payoutDetail: (((h['payout'] as Map?) ?? const {})['detail'] ?? '').toString(),
      note: (h['note'] ?? '').toString(),
    );
  }
}

class CreatorHubService {
  static Future<CreatorHub> load() async {
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    final res = await http.get(Uri.parse('${AiBackendConstants.baseUrl}/api/v1/creator/hub'),
        headers: {if (token != null) 'Authorization': 'Bearer $token'});
    if (res.statusCode == 403) throw Exception('Log into a real account to see your Creator Hub.');
    if (res.statusCode != 200) throw Exception('Could not load your Creator Hub (${res.statusCode})');
    return CreatorHub.fromJson(jsonDecode(res.body));
  }
}
