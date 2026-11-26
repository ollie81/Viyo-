import 'dart:convert';

import 'package:http/http.dart' as http;

import '../constants/supabase_constants.dart';
import 'supabase_service.dart';

double _d(Object? v) => (v as num?)?.toDouble() ?? 0;
int _i(Object? v) => (v as num?)?.toInt() ?? 0;
DateTime? _t(Object? v) => v == null ? null : DateTime.tryParse('$v');

/// A brand campaign as the server reports it. Paid (status 'open') only after NardoPay's signed payment webhook was
/// verified on the server; coming back from NardoPay never opens a campaign by itself.
class BrandCampaign {
  final String id, brandName, title, brief, deliverable, status;
  final String? link, paymentLink;
  final double feeUsd, creatorGetsUsd, budgetUsd, creditUsedUsd, payUsd, creditedBackUsd;
  final int slots;
  final DateTime? deadline;
  final Map<String, int> counts;
  final List<BrandApplication> applications;
  final BrandApplication? myApplication;

  const BrandCampaign({required this.id, required this.brandName, required this.title, this.brief = '',
      this.deliverable = '', required this.status, this.link, this.paymentLink, required this.feeUsd,
      required this.creatorGetsUsd, this.budgetUsd = 0, this.creditUsedUsd = 0, this.payUsd = 0,
      this.creditedBackUsd = 0, required this.slots, this.deadline, this.counts = const {},
      this.applications = const [], this.myApplication});

  bool get awaitingPayment => status == 'awaiting_payment';
  bool get isOpen => status == 'open';
  int count(String s) => counts[s] ?? 0;

  factory BrandCampaign.fromJson(Map j) => BrandCampaign(
        id: '${j['id']}',
        brandName: '${j['brand_name'] ?? ''}',
        title: '${j['title'] ?? ''}',
        brief: '${j['brief'] ?? ''}',
        deliverable: '${j['deliverable'] ?? ''}',
        status: '${j['status'] ?? ''}',
        link: j['link'] as String?,
        paymentLink: j['payment_link'] as String?,
        feeUsd: _d(j['fee_usd']),
        creatorGetsUsd: _d(j['creator_gets_usd']),
        budgetUsd: _d(j['budget_usd']),
        creditUsedUsd: _d(j['credit_used_usd']),
        payUsd: _d(j['pay_usd']),
        creditedBackUsd: _d(j['credited_back_usd']),
        slots: _i(j['slots']),
        deadline: _t(j['deadline']),
        counts: {for (final e in ((j['counts'] as Map?) ?? const {}).entries) '${e.key}': _i(e.value)},
        applications: [for (final a in (j['applications'] as List? ?? const [])) BrandApplication.fromJson(a as Map)],
        myApplication: j['my_application'] is Map ? BrandApplication.fromJson(j['my_application'] as Map) : null,
      );
}

/// A creator's application to a campaign, and what happened to it.
class BrandApplication {
  final String id, campaignId, status, pitch, decisionNote;
  final String? postId, creatorId, creatorName;
  final bool autoApproved;
  final DateTime? submittedAt, autoApprovesAt;
  final BrandCampaign? campaign;

  const BrandApplication({required this.id, required this.campaignId, required this.status, this.pitch = '',
      this.decisionNote = '', this.postId, this.creatorId, this.creatorName, this.autoApproved = false,
      this.submittedAt, this.autoApprovesAt, this.campaign});

  factory BrandApplication.fromJson(Map j) {
    final c = j['creator'] as Map?;
    return BrandApplication(
      id: '${j['id']}',
      campaignId: '${j['campaign_id']}',
      status: '${j['status'] ?? ''}',
      pitch: '${j['pitch'] ?? ''}',
      decisionNote: '${j['decision_note'] ?? ''}',
      postId: j['post_id'] as String?,
      creatorId: c?['id']?.toString(),
      creatorName: c?['name']?.toString(),
      autoApproved: j['auto_approved'] == true,
      submittedAt: _t(j['submitted_at']),
      autoApprovesAt: _t(j['auto_approves_at']),
      campaign: j['campaign'] is Map ? BrandCampaign.fromJson(j['campaign'] as Map) : null,
    );
  }
}

class CampaignOptions {
  final bool available, canPay;
  final double creatorShare, feeMinUsd, feeMaxUsd;
  final int slotsMax, daysMin, daysMax, autoApproveDays;
  final String minLevel;
  final double? feePercent;
  const CampaignOptions({required this.available, this.canPay = false, this.creatorShare = 0.8,
      this.feeMinUsd = 5, this.feeMaxUsd = 5000, this.slotsMax = 50, this.daysMin = 3, this.daysMax = 90,
      this.autoApproveDays = 7, this.minLevel = 'Rising', this.feePercent});
  factory CampaignOptions.fromJson(Map j) => CampaignOptions(
        available: j['available'] == true,
        canPay: j['can_pay'] == true,
        creatorShare: (j['creator_share'] as num?)?.toDouble() ?? 0.8,
        feeMinUsd: (j['fee_min_usd'] as num?)?.toDouble() ?? 5,
        feeMaxUsd: (j['fee_max_usd'] as num?)?.toDouble() ?? 5000,
        slotsMax: (j['slots_max'] as num?)?.toInt() ?? 50,
        daysMin: (j['days_min'] as num?)?.toInt() ?? 3,
        daysMax: (j['days_max'] as num?)?.toInt() ?? 90,
        autoApproveDays: (j['auto_approve_days'] as num?)?.toInt() ?? 7,
        minLevel: '${j['min_level'] ?? 'Rising'}',
        feePercent: (j['fee_percent'] as num?)?.toDouble(),
      );
}

class OpenCampaigns {
  final bool eligible;
  final String level, minLevel;
  final List<BrandCampaign> campaigns;
  const OpenCampaigns({required this.eligible, this.level = '', this.minLevel = 'Rising', this.campaigns = const []});
  factory OpenCampaigns.fromJson(Map j) => OpenCampaigns(
        eligible: j['eligible'] == true,
        level: '${j['level'] ?? ''}',
        minLevel: '${j['min_level'] ?? 'Rising'}',
        campaigns: [for (final c in (j['campaigns'] as List? ?? const [])) BrandCampaign.fromJson(c as Map)],
      );
}

class MyPost {
  final String id, caption;
  final String? thumbnailUrl;
  const MyPost({required this.id, this.caption = '', this.thumbnailUrl});
  factory MyPost.fromJson(Map j) =>
      MyPost(id: '${j['id']}', caption: '${j['caption'] ?? ''}', thumbnailUrl: j['thumbnail_url'] as String?);
}

/// The server calls for brand campaigns. A fake in tests.
class BrandCampaignApi {
  const BrandCampaignApi();

  static String get _base => '${AiBackendConstants.baseUrl}/api/v1/brand-campaigns';

  static Future<Map<String, String>> _headers() async {
    final token = SupabaseService.client.auth.currentSession?.accessToken;
    return {'Content-Type': 'application/json', if (token != null) 'Authorization': 'Bearer $token'};
  }

  static Map _ok(http.Response res) {
    if (res.statusCode == 200) return jsonDecode(res.body) as Map;
    String msg = 'Something went wrong (${res.statusCode}). Try again.';
    try {
      final d = jsonDecode(res.body)['detail'];
      if (d is String) msg = d;
    } catch (_) {}
    throw Exception(msg);
  }

  Future<Map> _get(String path) async =>
      _ok(await http.get(Uri.parse('$_base$path'), headers: await _headers()).timeout(const Duration(seconds: 20)));

  Future<Map> _post(String path, [Map? body]) async => _ok(await http
      .post(Uri.parse('$_base$path'), headers: await _headers(), body: jsonEncode(body ?? const {}))
      .timeout(const Duration(seconds: 30)));

  Future<CampaignOptions> options() async {
    try {
      final res = await http.get(Uri.parse('$_base/availability')).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return const CampaignOptions(available: false);
      return CampaignOptions.fromJson(jsonDecode(res.body) as Map);
    } catch (_) {
      return const CampaignOptions(available: false);
    }
  }

  Future<double> credit() async => _d((await _get('/credit'))['credit_usd']);

  Future<({List<BrandCampaign> campaigns, double creditUsd})> mine() async {
    final j = await _get('/mine');
    return (
      campaigns: [for (final c in (j['campaigns'] as List? ?? const [])) BrandCampaign.fromJson(c as Map)],
      creditUsd: _d(j['credit_usd']),
    );
  }

  Future<BrandCampaign> create({required String brandName, required String title, required String brief,
      String deliverable = '', String link = '', required int feeUsdCents, required int slots, required int days}) async =>
      BrandCampaign.fromJson(await _post('', {
        'brand_name': brandName, 'title': title, 'brief': brief, 'deliverable': deliverable, 'link': link,
        'fee_usd_cents': feeUsdCents, 'slots': slots, 'days': days,
      }));

  Future<BrandCampaign> detail(String id) async => BrandCampaign.fromJson(await _get('/$id'));

  Future<double> close(String id) async => _d((await _post('/$id/close'))['credited_usd']);

  /// The business: accept | decline | approve | reject (a reason is required to reject).
  Future<BrandApplication> decide(String applicationId, String action, {String note = ''}) async =>
      BrandApplication.fromJson(await _post('/applications/$applicationId/$action', {'note': note}));

  Future<OpenCampaigns> open() async => OpenCampaigns.fromJson(await _get('/creator/open'));

  Future<List<BrandApplication>> deals() async =>
      [for (final a in ((await _get('/creator/deals'))['deals'] as List? ?? const [])) BrandApplication.fromJson(a as Map)];

  Future<List<MyPost>> myPosts() async =>
      [for (final p in ((await _get('/creator/posts'))['posts'] as List? ?? const [])) MyPost.fromJson(p as Map)];

  Future<BrandApplication> apply(String campaignId, String pitch) async =>
      BrandApplication.fromJson(await _post('/$campaignId/apply', {'pitch': pitch}));

  Future<BrandApplication> submit(String applicationId, String postId) async =>
      BrandApplication.fromJson(await _post('/applications/$applicationId/submit', {'post_id': postId}));

  Future<BrandApplication> withdraw(String applicationId) async =>
      BrandApplication.fromJson(await _post('/applications/$applicationId/withdraw'));
}

String usd(double v) => v == v.roundToDouble() ? '\$${v.toStringAsFixed(0)}' : '\$${v.toStringAsFixed(2)}';
