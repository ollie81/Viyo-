import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:viyo/models/post.dart';
import 'package:viyo/screens/creator/brand_campaigns_screen.dart';
import 'package:viyo/screens/creator/brand_deals_screen.dart';
import 'package:viyo/services/brand_campaign_service.dart';
import 'package:viyo/services/pending_purchase.dart';

BrandCampaign campaign({String status = 'open', List<BrandApplication> apps = const [], BrandApplication? mine}) =>
    BrandCampaign(
      id: 'c1', brandName: 'Inyange', title: 'Summer juice', brief: 'Show our mango juice in a fun video.',
      deliverable: 'One video', status: status, feeUsd: 50, creatorGetsUsd: 40, budgetUsd: 100, slots: 2,
      deadline: DateTime.utc(2026, 12, 10), applications: apps, myApplication: mine,
    );

class FakeApi extends BrandCampaignApi {
  FakeApi({this.creditUsd = 0, this.eligible = true, this.detailCampaign, this.myDeals = const []});
  final double creditUsd;
  final bool eligible;
  BrandCampaign? detailCampaign;
  List<BrandApplication> myDeals;
  final created = <Map<String, Object>>[];
  final decisions = <(String, String, String)>[];
  final applied = <(String, String)>[];
  final submitted = <(String, String)>[];

  @override
  Future<CampaignOptions> options() async => const CampaignOptions(available: true, canPay: true, feePercent: 17);
  @override
  Future<double> credit() async => creditUsd;
  @override
  Future<({List<BrandCampaign> campaigns, double creditUsd})> mine() async =>
      (campaigns: [campaign(apps: const [])], creditUsd: creditUsd);
  @override
  Future<BrandCampaign> create({required String brandName, required String title, required String brief,
      String deliverable = '', String link = '', required int feeUsdCents, required int slots, required int days}) async {
    created.add({'brand': brandName, 'fee': feeUsdCents, 'slots': slots, 'days': days});
    return detailCampaign = campaign();
  }

  @override
  Future<BrandCampaign> detail(String id) async => detailCampaign ?? campaign();
  @override
  Future<BrandApplication> decide(String applicationId, String action, {String note = ''}) async {
    decisions.add((applicationId, action, note));
    return BrandApplication(id: applicationId, campaignId: 'c1', status: action);
  }

  @override
  Future<OpenCampaigns> open() async =>
      OpenCampaigns(eligible: eligible, level: eligible ? 'Rising' : 'New', campaigns: [campaign()]);
  @override
  Future<List<BrandApplication>> deals() async => myDeals;
  @override
  Future<List<MyPost>> myPosts() async => const [MyPost(id: 'p1', caption: 'My juice video')];
  @override
  Future<BrandApplication> apply(String campaignId, String pitch) async {
    applied.add((campaignId, pitch));
    return BrandApplication(id: 'a1', campaignId: campaignId, status: 'applied');
  }

  @override
  Future<BrandApplication> submit(String applicationId, String postId) async {
    submitted.add((applicationId, postId));
    return BrandApplication(id: applicationId, campaignId: 'c1', status: 'submitted', postId: postId);
  }
}

Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 8; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> show(WidgetTester t, Widget w, {double width = 390}) async {
  t.view.physicalSize = Size(width, 2400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(theme: ThemeData.dark(), home: w));
  await settle(t);
}

Future<void> tap(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pump();
  await t.tap(f);
  await settle(t);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('models: campaign, application, sponsored post, and a pending campaign payment', () async {
    final c = BrandCampaign.fromJson({
      'id': 'c1', 'brand_name': 'Inyange', 'title': 'T', 'status': 'awaiting_payment', 'fee_usd': 50,
      'creator_gets_usd': 40, 'slots': 2, 'pay_usd': 100, 'payment_link': 'https://nardopay.com/p/x',
      'counts': {'submitted': 1},
      'applications': [{'id': 'a1', 'campaign_id': 'c1', 'status': 'submitted', 'post_id': 'p1',
          'creator': {'id': 'u', 'name': 'Amani'}, 'auto_approves_at': '2026-12-03T10:00:00Z'}],
    });
    expect(c.awaitingPayment, isTrue);
    expect(c.count('submitted'), 1);
    expect(c.applications.single.creatorName, 'Amani');
    expect(c.applications.single.autoApprovesAt, isNotNull);
    final p = Post.fromJson({'id': 'p', 'user_id': 'u', 'created_at': '2026-11-26T10:00:00Z', 'post_type': 'video',
        'sponsored_by': 'Inyange'});
    expect(p.isSponsored, isTrue);
    expect(Post.fromJson({'id': 'p', 'user_id': 'u', 'created_at': '2026-11-26T10:00:00Z', 'post_type': 'video'})
        .isSponsored, isFalse);
    await PendingPurchase.save('campaign', 'c1');
    expect((await PendingPurchase.peek())?.kind, 'campaign');
    expect(usd(40), r'$40');
    expect(usd(12.5), r'$12.50');
  });

  for (final width in [390.0, 1280.0]) {
    testWidgets('new campaign: budget in dollars, credit used first, what each creator gets (width $width)', (t) async {
      final api = FakeApi(creditUsd: 30);
      await show(t, NewCampaignScreen(api: api), width: width);
      await t.enterText(find.byType(TextField).at(0), 'Inyange');
      await t.enterText(find.byType(TextField).at(1), 'Summer juice');
      await t.enterText(find.byType(TextField).at(2), 'Show our new mango juice in a fun video.');
      await settle(t);
      expect(find.text(r'$150'), findsOneWidget);                         // $50 x 3 creators
      expect(find.text(r'−$30'), findsOneWidget);                         // credit used
      expect(find.text(r'$120 + fee'), findsOneWidget);
      expect(find.textContaining(r'Each creator gets $40 (80% of the fee)'), findsOneWidget);
      expect(find.textContaining('about 17%'), findsOneWidget);
      expect(find.text(r'Pay $120 + fee by card'), findsOneWidget);
      expect(find.textContaining('RWF'), findsNothing);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('a campaign fully covered by credit starts without a payment and opens its page', (t) async {
    final api = FakeApi(creditUsd: 1000);
    await show(t, NewCampaignScreen(api: api));
    await t.enterText(find.byType(TextField).at(0), 'Inyange');
    await t.enterText(find.byType(TextField).at(1), 'Summer juice');
    await t.enterText(find.byType(TextField).at(2), 'Show our new mango juice in a fun video.');
    await settle(t);
    await tap(t, find.text('Start campaign'));
    expect(api.created.single, {'brand': 'Inyange', 'fee': 5000, 'slots': 3, 'days': 14});
    expect(find.text('Summer juice'), findsOneWidget);                   // the campaign page
  });

  testWidgets('the business picks applicants and approves or (with a reason) rejects posts', (t) async {
    final api = FakeApi(detailCampaign: campaign(apps: const [
      BrandApplication(id: 'a1', campaignId: 'c1', status: 'applied', pitch: 'I love mango', creatorName: 'Amani'),
      BrandApplication(id: 'a2', campaignId: 'c1', status: 'submitted', postId: 'p1', creatorName: 'Keza'),
    ]));
    await show(t, CampaignDetailScreen(campaignId: 'c1', api: api));
    expect(find.text('Posts to review (1)'), findsOneWidget);
    expect(find.text('Applicants (1)'), findsOneWidget);
    expect(find.text('I love mango'), findsOneWidget);
    await tap(t, find.text('Pick'));
    expect(api.decisions.last, ('a1', 'accept', ''));
    await tap(t, find.text(r'Approve · pay $40'));
    expect(api.decisions.last, ('a2', 'approve', ''));
    await tap(t, find.text("Don't approve").first);
    await t.enterText(find.byType(TextField).last, 'The juice is not shown');
    await tap(t, find.text("Don't approve").last);
    expect(api.decisions.last, ('a2', 'reject', 'The juice is not shown'));
  });

  testWidgets('creators below Rising see why and cannot apply', (t) async {
    await show(t, BrandDealsScreen(api: FakeApi(eligible: false)));
    expect(find.textContaining('Brand deals are for Rising creators and above'), findsOneWidget);
    final apply = t.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Apply'));
    expect(apply.onPressed, isNull);
  });

  testWidgets('a creator applies, then submits their post once picked', (t) async {
    final api = FakeApi();
    await show(t, BrandDealsScreen(api: api));
    expect(find.text(r'$40'), findsOneWidget);                            // what the creator gets
    await tap(t, find.widgetWithText(ElevatedButton, 'Apply'));
    await t.enterText(find.byType(TextField).last, 'My idea');
    await tap(t, find.widgetWithText(TextButton, 'Apply'));
    expect(api.applied.single, ('c1', 'My idea'));
    api.myDeals = [BrandApplication(id: 'a1', campaignId: 'c1', status: 'accepted', campaign: campaign())];
    await show(t, BrandDealsScreen(key: UniqueKey(), api: api));
    await tap(t, find.text('My deals (1)'));
    expect(find.textContaining("You're in!"), findsOneWidget);
    await tap(t, find.text('Submit your post'));
    expect(find.textContaining('labelled "Sponsored"'), findsOneWidget);
    await tap(t, find.text('My juice video'));
    expect(api.submitted.single, ('a1', 'p1'));
  });
}
