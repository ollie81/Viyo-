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
  final CreatorDashboard? dashboard;
  CreatorHub({required this.views, required this.likes, required this.comments, required this.shares, this.followers,
      required this.lifetimeCoins, required this.availableCoins, required this.pendingCoins, required this.paidCoins,
      required this.last30Coins, required this.lifetimeUsd, required this.availableUsd, required this.paidUsd,
      required this.canWithdraw, required this.payoutDetailsSaved, required this.withdrawalPending,
      required this.productions, required this.earns, required this.doesNotEarn, required this.payoutDetail,
      required this.note, this.dashboard});

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
      dashboard: j['dashboard'] is Map ? CreatorDashboard.fromJson(j['dashboard'] as Map) : null,
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

/// Audience analytics from the server (creator_analytics.py): every number counts each person once.
class CreatorAnalytics {
  final int uniqueViewers, completers, engagedViewers, followers, newFollowers, earnedCoins;
  final double watchMinutes;
  final List<Map<String, dynamic>> productions;
  final List<({String text, String basedOn})> advice;
  final String note;
  CreatorAnalytics({required this.uniqueViewers, required this.completers, required this.engagedViewers,
      required this.followers, required this.newFollowers, required this.earnedCoins, required this.watchMinutes,
      required this.productions, required this.advice, required this.note});

  factory CreatorAnalytics.fromJson(Map<String, dynamic> j) {
    final t = (j['totals'] as Map?) ?? const {};
    int i(String k) => (t[k] as num?)?.toInt() ?? 0;
    return CreatorAnalytics(
      uniqueViewers: i('unique_viewers'), completers: i('completers'), engagedViewers: i('engaged_viewers'),
      followers: i('followers'), newFollowers: i('new_followers'), earnedCoins: i('earned_coins'),
      watchMinutes: (t['watch_minutes'] as num?)?.toDouble() ?? 0,
      productions: [for (final p in (j['productions'] as List? ?? const [])) Map<String, dynamic>.from(p as Map)],
      advice: [
        for (final a in (j['advice'] as List? ?? const []))
          (text: ((a as Map)['text'] ?? '').toString(), basedOn: (a['based_on'] ?? '').toString()),
      ],
      note: (j['note'] ?? '').toString(),
    );
  }

  static Future<CreatorAnalytics?> load({int days = 30}) async {
    try {
      final token = Supabase.instance.client.auth.currentSession?.accessToken;
      final res = await http.get(Uri.parse('${AiBackendConstants.baseUrl}/api/v1/creator/analytics?days=$days'),
          headers: {if (token != null) 'Authorization': 'Bearer $token'});
      if (res.statusCode != 200) return null;
      return CreatorAnalytics.fromJson(jsonDecode(res.body));
    } catch (_) {
      return null;
    }
  }
}

/// One earning type in the dashboard (content, donations, adjustments), in coins from the earnings ledger.
class EarningType {
  final int coins, heldCoins, availableCoins, requestedCoins, paidCoins;
  final double usd;
  const EarningType({this.coins = 0, this.usd = 0, this.heldCoins = 0, this.availableCoins = 0,
      this.requestedCoins = 0, this.paidCoins = 0});
  factory EarningType.fromJson(Map j) => EarningType(
        coins: (j['coins'] as num?)?.toInt() ?? 0,
        usd: (j['usd'] as num?)?.toDouble() ?? 0,
        heldCoins: (j['held_coins'] as num?)?.toInt() ?? 0,
        availableCoins: (j['available_coins'] as num?)?.toInt() ?? 0,
        requestedCoins: (j['requested_coins'] as num?)?.toInt() ?? 0,
        paidCoins: (j['paid_coins'] as num?)?.toInt() ?? 0,
      );
}

/// The unified creator dashboard from the server (creator_hub.dashboard): exact counts from real records.
/// When [ready] is false the server couldn't add them up yet, and the app shows nothing estimated.
class CreatorDashboard {
  final bool ready;
  final int days;
  final DateTime? computedAt;
  final int plays, uniqueViewers, watchMinutes;
  final double? completionRate;
  final Map<String, EarningType> byType;
  final String? advertisingNote, brandNote;
  final int heldCoins, availableCoins, holdDays;
  final double heldUsd, availableUsd;
  final List<({String status, double usd, DateTime? createdAt, DateTime? paidAt})> withdrawals;
  final int projects, activeJobs, completedJobs, failedJobs, creditsUsed, creditsUsedPeriod;
  final CreatorLevel? level;

  const CreatorDashboard({this.level, required this.ready, this.days = 30, this.computedAt, this.plays = 0,
      this.uniqueViewers = 0, this.watchMinutes = 0, this.completionRate, this.byType = const {},
      this.advertisingNote, this.brandNote, this.heldCoins = 0, this.availableCoins = 0, this.holdDays = 14,
      this.heldUsd = 0, this.availableUsd = 0, this.withdrawals = const [], this.projects = 0, this.activeJobs = 0,
      this.completedJobs = 0, this.failedJobs = 0, this.creditsUsed = 0, this.creditsUsedPeriod = 0});

  static String? _notYet(Object? m) =>
      m is Map && m['available'] != true ? (m['note'] ?? 'Not available on VIYO yet.').toString() : null;

  factory CreatorDashboard.fromJson(Map j) {
    final a = (j['audience'] as Map?) ?? const {};
    final e = (j['earnings'] as Map?) ?? const {};
    final s = (j['studio'] as Map?) ?? const {};
    int i(Map m, String k) => (m[k] as num?)?.toInt() ?? 0;
    double d(Map m, String k) => (m[k] as num?)?.toDouble() ?? 0;
    return CreatorDashboard(
      ready: j['ready'] == true,
      days: (j['days'] as num?)?.toInt() ?? 30,
      computedAt: DateTime.tryParse((j['computed_at'] ?? '').toString()),
      plays: i(a, 'plays'), uniqueViewers: i(a, 'unique_viewers'), watchMinutes: i(a, 'watch_minutes'),
      completionRate: (a['completion_rate'] as num?)?.toDouble(),
      byType: {
        for (final en in ((e['by_type'] as Map?) ?? const {}).entries)
          en.key.toString(): EarningType.fromJson(en.value as Map),
      },
      advertisingNote: _notYet(e['advertising'] ?? j['advertising']),
      brandNote: _notYet(e['brand_campaigns'] ?? j['brand_campaigns']),
      heldCoins: i(e, 'held_coins'), availableCoins: i(e, 'available_coins'),
      holdDays: (e['hold_days'] as num?)?.toInt() ?? 14,
      heldUsd: d(e, 'held_usd'), availableUsd: d(e, 'available_usd'),
      withdrawals: [
        for (final w in (j['withdrawals'] as List? ?? const []))
          (
            status: ((w as Map)['status'] ?? '').toString(),
            usd: (w['usd'] as num?)?.toDouble() ?? 0,
            createdAt: DateTime.tryParse((w['created_at'] ?? '').toString()),
            paidAt: DateTime.tryParse((w['paid_at'] ?? '').toString()),
          ),
      ],
      projects: i(s, 'projects'), activeJobs: i(s, 'active_jobs'), completedJobs: i(s, 'completed_jobs'),
      failedJobs: i(s, 'failed_jobs'), creditsUsed: i(s, 'credits_used'), creditsUsedPeriod: i(s, 'credits_used_period'),
      level: j['level'] is Map ? CreatorLevel.fromJson(j['level'] as Map) : null,
    );
  }
}

/// One requirement for the next creator level, with the creator's real number (creator_levels.py).
class LevelRequirement {
  final String key, label;
  final num have, need;
  final bool met;
  const LevelRequirement({required this.key, required this.label, required this.have, required this.need, required this.met});
  factory LevelRequirement.fromJson(Map j) => LevelRequirement(
        key: (j['key'] ?? '').toString(),
        label: (j['label'] ?? '').toString(),
        have: (j['have'] as num?) ?? 0,
        need: (j['need'] as num?) ?? 0,
        met: j['met'] == true,
      );

  /// 0..1 towards this requirement (the clean-record one is all or nothing).
  double get progress => met ? 1 : (key == 'clean' || need <= 0 ? 0 : (have / need).clamp(0, 1).toDouble());
}

/// The creator's level (New, Rising, Pro, Star). Everyone earns the same share; Pro and Star get a shorter hold.
class CreatorLevel {
  final String key, name, shareNote;
  final int rank, of, holdDays;
  final bool ready;
  final List<String> perks;
  final String? nextName, nextPerk;
  final List<LevelRequirement> nextRequirements;
  const CreatorLevel({required this.key, required this.name, required this.rank, required this.of,
      required this.holdDays, this.ready = true, this.perks = const [], this.shareNote = '', this.nextName,
      this.nextPerk, this.nextRequirements = const []});
  factory CreatorLevel.fromJson(Map j) {
    final n = j['next'] as Map?;
    return CreatorLevel(
      key: (j['key'] ?? 'new').toString(),
      name: (j['name'] ?? 'New').toString(),
      rank: (j['rank'] as num?)?.toInt() ?? 1,
      of: (j['of'] as num?)?.toInt() ?? 4,
      holdDays: (j['hold_days'] as num?)?.toInt() ?? 14,
      ready: j['ready'] != false,
      perks: ((j['perks'] as List?) ?? const []).map((e) => e.toString()).toList(),
      shareNote: (j['share_note'] ?? '').toString(),
      nextName: n?['name']?.toString(),
      nextPerk: n?['perk']?.toString(),
      nextRequirements: [for (final r in (n?['requirements'] as List? ?? const [])) LevelRequirement.fromJson(r as Map)],
    );
  }
}
