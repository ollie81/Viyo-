import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../constants/supabase_constants.dart';

class AdStats {
  final int views, likes, comments, shares;
  final double? engagementRate;
  AdStats({this.views = 0, this.likes = 0, this.comments = 0, this.shares = 0, this.engagementRate});
  factory AdStats.fromJson(Map j) => AdStats(
        views: (j['views'] as num?)?.toInt() ?? 0,
        likes: (j['likes'] as num?)?.toInt() ?? 0,
        comments: (j['comments'] as num?)?.toInt() ?? 0,
        shares: (j['shares'] as num?)?.toInt() ?? 0,
        engagementRate: (j['engagement_rate'] as num?)?.toDouble(),
      );
}

class AdInsightPost {
  final String postId;
  final String? campaignId;
  final String caption;
  final String? thumbnailUrl;
  final bool paid;
  final bool public;
  final AdStats stats;
  AdInsightPost({required this.postId, this.campaignId, required this.caption, this.thumbnailUrl, required this.paid,
      required this.public, required this.stats});
}

class AdTrendDay {
  final String day;
  final int likes, comments;
  final int? views, shares; // null: no snapshot to compare with that day
  AdTrendDay({required this.day, required this.likes, required this.comments, this.views, this.shares});
}

class AdInsights {
  final int days;
  final AdStats organic, paid;
  final int organicAds, paidAds;
  final List<AdInsightPost> posts;
  final List<AdTrendDay> trend;
  final int? followers, followersGained;
  final List<String> notes;
  AdInsights({required this.days, required this.organic, required this.paid, required this.organicAds,
      required this.paidAds, required this.posts, required this.trend, this.followers, this.followersGained,
      required this.notes});

  factory AdInsights.fromJson(Map<String, dynamic> j) {
    final t = (j['totals'] as Map?) ?? const {};
    final f = (j['followers'] as Map?) ?? const {};
    return AdInsights(
      days: (j['days'] as num?)?.toInt() ?? 30,
      organic: AdStats.fromJson((t['organic'] as Map?) ?? const {}),
      paid: AdStats.fromJson((t['paid'] as Map?) ?? const {}),
      organicAds: ((t['organic'] as Map?)?['ads'] as num?)?.toInt() ?? 0,
      paidAds: ((t['paid'] as Map?)?['ads'] as num?)?.toInt() ?? 0,
      posts: [
        for (final p in (j['posts'] as List? ?? const []))
          AdInsightPost(
            postId: (p as Map)['post_id'].toString(),
            campaignId: p['campaign_id'] as String?,
            caption: (p['caption'] ?? '').toString(),
            thumbnailUrl: p['thumbnail_url'] as String?,
            paid: p['paid'] == true,
            public: p['public'] != false,
            stats: AdStats.fromJson(p),
          ),
      ],
      trend: [
        for (final d in (j['trend'] as List? ?? const []))
          AdTrendDay(
            day: (d as Map)['day'].toString(),
            likes: (d['likes'] as num?)?.toInt() ?? 0,
            comments: (d['comments'] as num?)?.toInt() ?? 0,
            views: (d['views'] as num?)?.toInt(),
            shares: (d['shares'] as num?)?.toInt(),
          ),
      ],
      followers: (f['total'] as num?)?.toInt(),
      followersGained: (f['gained'] as num?)?.toInt(),
      notes: ((j['notes'] as List?) ?? []).map((e) => e.toString()).toList(),
    );
  }
}

class AdVariant {
  final String campaignId;
  final String tone;
  final String label;
  final String status;
  final bool published;
  final bool public;
  final AdStats? stats;
  final String? thumbnailUrl;
  AdVariant({required this.campaignId, required this.tone, required this.label, required this.status,
      required this.published, required this.public, this.stats, this.thumbnailUrl});
}

class AdExperiment {
  final String id;
  final String name;
  final String? brandId;
  final List<AdVariant> variants;
  final String verdict; // not_enough_data | no_clear_difference | leader
  final String? leader;
  final String message;
  AdExperiment({required this.id, required this.name, this.brandId, required this.variants, required this.verdict,
      this.leader, required this.message});

  factory AdExperiment.fromJson(Map<String, dynamic> j) {
    final c = (j['comparison'] as Map?) ?? const {};
    return AdExperiment(
      id: j['id'] as String,
      name: (j['name'] ?? '').toString(),
      brandId: j['brand_id'] as String?,
      variants: [
        for (final v in (j['variants'] as List? ?? const []))
          AdVariant(
            campaignId: (v as Map)['campaign_id'].toString(),
            tone: (v['tone'] ?? '').toString(),
            label: (v['label'] ?? '').toString(),
            status: (v['status'] ?? 'draft').toString(),
            published: v['published'] == true,
            public: v['public'] == true,
            stats: v['stats'] is Map ? AdStats.fromJson(v['stats'] as Map) : null,
            thumbnailUrl: v['thumbnail_url'] as String?,
          ),
      ],
      verdict: (c['verdict'] ?? 'not_enough_data').toString(),
      leader: c['leader'] as String?,
      message: (c['message'] ?? '').toString(),
    );
  }
}

/// Insights and experiments for the creator's own ads (creator sign-in, never an admin key).
class AdInsightsService {
  static const _base = '${AiBackendConstants.baseUrl}/api/v1/ads-maker';

  static Map<String, String> get _headers {
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    return {'Content-Type': 'application/json', if (token != null) 'Authorization': 'Bearer $token'};
  }

  static Exception _failure(http.Response res, String action) {
    try {
      final d = jsonDecode(res.body)['detail'];
      if (d is String) return Exception(d);
    } catch (_) {}
    return Exception('Could not $action (${res.statusCode})');
  }

  static Future<AdInsights> insights({int days = 30}) async {
    final res = await http.get(Uri.parse('$_base/insights?days=$days'), headers: _headers);
    if (res.statusCode != 200) throw _failure(res, 'load insights');
    return AdInsights.fromJson(jsonDecode(res.body));
  }

  static Future<List<AdExperiment>> experiments() async {
    final res = await http.get(Uri.parse('$_base/experiments'), headers: _headers);
    if (res.statusCode != 200) throw _failure(res, 'load experiments');
    return (jsonDecode(res.body) as List).map((e) => AdExperiment.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<AdExperiment> experiment(String id) async {
    final res = await http.get(Uri.parse('$_base/experiments/$id'), headers: _headers);
    if (res.statusCode != 200) throw _failure(res, 'load the experiment');
    return AdExperiment.fromJson(jsonDecode(res.body));
  }

  /// Versions of an ad in different tones, as drafts (nothing charged until each is generated).
  static Future<AdExperiment> createExperiment(String brandId, List<String> tones,
      {String aspectRatio = '9:16', bool useCharacter = true, String? ideaId}) async {
    final res = await http.post(Uri.parse('$_base/brands/$brandId/experiments'),
        headers: _headers,
        body: jsonEncode({
          'tones': tones,
          'aspect_ratio': aspectRatio,
          'use_character': useCharacter,
          if (ideaId != null) 'idea_id': ideaId,
        }));
    if (res.statusCode != 200) throw _failure(res, 'start the experiment');
    return AdExperiment.fromJson(jsonDecode(res.body));
  }
}
