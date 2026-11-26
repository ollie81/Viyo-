import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viyo/screens/admin/ad_revenue_admin_screen.dart';
import 'package:viyo/screens/creator/creator_hub_screen.dart';
import 'package:viyo/services/ad_revenue_service.dart';
import 'package:viyo/services/creator_hub_service.dart';

Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Map<String, dynamic> hub({required bool adsOn}) => {
      'audience': {'views': 10},
      'earnings': {},
      'productions': [],
      'how_you_earn': {'earns': [], 'does_not_earn': [], 'payout': {'detail': ''}},
      'dashboard': {
        'ready': true,
        'days': 30,
        'audience': {},
        'earnings': {
          'by_type': {
            'ads': {'coins': 1666, 'usd': 10.0, 'held_coins': 1666},
          },
          'advertising': adsOn ? {'available': true, 'note': 'x'} : {'available': false, 'note': 'Not available'},
          'brand_campaigns': {'available': false},
          'hold_days': 14,
        },
        'withdrawals': [],
        'studio': {},
      },
    };

const summary = AdRevenueSummary(
  available: true,
  thisMonth: AdRevenueMonth(month: '2026-11', feedAds: 120, unlockAds: 40),
  months: [AdRevenueMonth(month: '2026-10', feedAds: 300, unlockAds: 80, usd: 10)],
);

Future<void> openHub(WidgetTester t, {required bool adsOn}) async {
  t.view.physicalSize = const Size(390, 4000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    theme: ThemeData.dark(),
    home: CreatorHubScreen(
      loadHub: () async => CreatorHub.fromJson(hub(adsOn: adsOn)),
      loadAnalytics: () async => null,
      loadAdRevenue: () async => summary,
    ),
  ));
  await settle(t);
}

void main() {
  test('the summary reads counts and closed months', () {
    final s = AdRevenueSummary.fromJson({
      'available': true, 'creator_share': 0.5,
      'this_month': {'month': '2026-11', 'feed_ads': 3, 'unlock_ads': 2},
      'months': [{'month': '2026-10', 'feed_ads': 5, 'unlock_ads': 4, 'usd': 1.25}],
    });
    expect(s.thisMonth.feedAds, 3);
    expect(s.months.single.usd, 1.25);
    expect(AdRevenueSummary.fromJson({}).available, isFalse);
  });

  testWidgets('creators see ads on their content this month and what closed months paid', (t) async {
    await openHub(t, adsOn: true);
    expect(find.text('Ad revenue'), findsNWidgets(2));                    // the section and the earnings row
    expect(find.text('This month so far: 160 ads on your content'), findsOneWidget);
    expect(find.textContaining('You get 50% of what these ads really earn'), findsOneWidget);
    expect(find.text('Oct 2026'), findsOneWidget);
    expect(find.text(r'$10.00'), findsWidgets);
    expect(find.text('Not available yet'), findsOneWidget);               // brand campaigns still off here
  });

  testWidgets('before it is set up: no ad section, "Not available yet"', (t) async {
    await openHub(t, adsOn: false);
    expect(find.textContaining('This month so far'), findsNothing);
    expect(find.text('Not available yet'), findsNWidgets(2));
  });

  testWidgets('admin: check last month, enter the AdMob totals, confirm, close once', (t) async {
    final closed = <(String, double, double)>[];
    t.view.physicalSize = const Size(390, 1600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      home: AdRevenueAdminScreen(
        now: DateTime.utc(2026, 12, 3),
        month: (key, m) async => {'can_close': true, 'closed': false, 'feed_ads': 400, 'unlock_ads': 100, 'creators': 7},
        close: (key, m, f, u, n) async {
          closed.add((m, f, u));
          return {'paid_usd': 25.0, 'creators': 7};
        },
      ),
    ));
    expect(find.text('Month: 2026-11'), findsOneWidget);
    await t.tap(find.text('Check'));
    await settle(t);
    expect(find.text('Enter the admin key.'), findsOneWidget);
    await t.enterText(find.byType(TextField).first, 'k');
    await t.tap(find.text('Check'));
    await settle(t);
    expect(find.textContaining("400 in-feed ads and 100 unlock ads on 7 creators"), findsOneWidget);
    await t.enterText(find.byType(TextField).at(1), '40');
    await t.enterText(find.byType(TextField).at(2), '10');
    await settle(t);
    await t.tap(find.text('Close the month and pay creators'));
    await settle(t);
    expect(find.textContaining(r'Creators get half: $25.00'), findsOneWidget);
    await t.tap(find.text('Close the month'));
    await settle(t);
    expect(closed.single, ('2026-11', 40.0, 10.0));
    expect(find.textContaining(r'Closed. $25.00 credited to 7 creators'), findsOneWidget);
  });
}
