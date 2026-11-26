import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viyo/screens/creator/creator_hub_screen.dart';
import 'package:viyo/services/creator_hub_service.dart';

Map<String, dynamic> hubJson({Map<String, dynamic>? dashboard}) => {
      'audience': {'views': 6700, 'likes': 90, 'comments': 5, 'shares': 2},
      'earnings': {'available_coins': 200, 'available_usd': 1.2, 'lifetime_usd': 1.8},
      'productions': [],
      'how_you_earn': {'earns': [], 'does_not_earn': [], 'payout': {'detail': ''}},
      if (dashboard != null) 'dashboard': dashboard,
    };

const readyDashboard = {
  'ready': true,
  'days': 30,
  'computed_at': '2026-11-26T10:00:00Z',
  'audience': {'plays': 3, 'unique_viewers': 2, 'watch_minutes': 4, 'completion_rate': 0.333},
  'earnings': {
    'by_type': {
      'content': {'coins': 600, 'usd': 3.6, 'held_coins': 100, 'available_coins': 200, 'requested_coins': 0, 'paid_coins': 300},
      'donations': {'coins': 1333, 'usd': 8.0, 'held_coins': 1333, 'available_coins': 0, 'requested_coins': 0, 'paid_coins': 0},
      'adjustments': {'coins': 0, 'usd': 0, 'held_coins': 0, 'available_coins': 0, 'requested_coins': 0, 'paid_coins': 0},
    },
    'advertising': {'available': false, 'note': 'Not available on VIYO yet.'},
    'brand_campaigns': {'available': false, 'note': 'Not available on VIYO yet.'},
    'held_coins': 1433, 'held_usd': 8.6, 'available_coins': 200, 'available_usd': 1.2, 'hold_days': 14,
  },
  'withdrawals': [
    {'status': 'paid', 'usd': 12.0, 'created_at': '2026-11-01T10:00:00Z', 'paid_at': '2026-11-03T10:00:00Z'},
  ],
  'studio': {'projects': 1, 'active_jobs': 1, 'completed_jobs': 2, 'failed_jobs': 1, 'credits_used': 100, 'credits_used_period': 40},
};

Future<int> open(WidgetTester t, Map<String, dynamic> json, {double width = 390}) async {
  var calls = 0;
  t.view.physicalSize = Size(width, 4000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    theme: ThemeData.dark(),
    home: CreatorHubScreen(
      loadHub: () async {
        calls++;
        return CreatorHub.fromJson(json);
      },
      loadAnalytics: () async => null,
    ),
  ));
  await t.pump(const Duration(milliseconds: 100));
  return calls;
}

void main() {
  test('the dashboard reads exact numbers; ads and brand campaigns are not available', () {
    final d = CreatorHub.fromJson(hubJson(dashboard: readyDashboard)).dashboard!;
    expect(d.ready, isTrue);
    expect(d.plays, 3);
    expect(d.completionRate, 0.333);
    expect(d.byType['donations']!.heldCoins, 1333);
    expect(d.advertisingNote, 'Not available on VIYO yet.');
    expect(d.brandNote, isNotNull);
    expect(d.withdrawals.single.usd, 12.0);
    expect(d.creditsUsedPeriod, 40);
  });

  test('an older server without the dashboard, or one not ready, estimates nothing', () {
    expect(CreatorHub.fromJson(hubJson()).dashboard, isNull);
    final d = CreatorHub.fromJson(hubJson(dashboard: {'ready': false, 'days': 30})).dashboard!;
    expect(d.ready, isFalse);
    expect(d.plays, 0);
    expect(d.byType, isEmpty);
  });

  for (final width in [390.0, 1280.0]) {
    testWidgets('one screen: audience, earnings by type, withdrawals and Studio (width $width)', (t) async {
      await open(t, hubJson(dashboard: readyDashboard), width: width);
      expect(find.text('Last 30 days'), findsOneWidget);
      expect(find.text('Plays'), findsOneWidget);
      expect(find.text('33%'), findsOneWidget);
      expect(find.text('Earnings by type'), findsOneWidget);
      expect(find.text('Paid content'), findsOneWidget);
      expect(find.text(r'$8.00'), findsOneWidget);                      // donations
      expect(find.text('Refunds and corrections'), findsNothing);       // nothing to show
      expect(find.text('Ad revenue'), findsOneWidget);
      expect(find.text('Brand campaigns'), findsOneWidget);
      expect(find.text('Not available yet'), findsNWidgets(2));
      expect(find.text(r'$8.60'), findsOneWidget);                      // on hold
      expect(find.textContaining('held for 14 days'), findsOneWidget);
      expect(find.text('Withdrawals'), findsOneWidget);
      expect(find.text('Paid'), findsOneWidget);
      expect(find.text('Studio'), findsOneWidget);
      expect(find.textContaining('40 credits used in the last 30 days'), findsOneWidget);
      expect(find.textContaining('refreshes every minute'), findsOneWidget);
      expect(find.textContaining('RWF'), findsNothing);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('not ready: no breakdown, a plain note, no made-up numbers', (t) async {
    await open(t, hubJson(dashboard: {'ready': false, 'days': 30}));
    expect(find.text('Earnings by type'), findsNothing);
    expect(find.text('Studio'), findsNothing);
    expect(find.textContaining('being set up'), findsOneWidget);
  });

  testWidgets('it refreshes itself every minute while open, and stops when closed', (t) async {
    var calls = 0;
    await t.pumpWidget(MaterialApp(
      home: CreatorHubScreen(
        loadHub: () async {
          calls++;
          return CreatorHub.fromJson(hubJson(dashboard: readyDashboard));
        },
        loadAnalytics: () async => null,
      ),
    ));
    await t.pump(const Duration(milliseconds: 100));
    expect(calls, 1);
    await t.pump(CreatorHubScreen.refreshEvery);
    await t.pump(const Duration(milliseconds: 100));
    expect(calls, 2);
    await t.pumpWidget(const SizedBox());
    await t.pump(CreatorHubScreen.refreshEvery * 2);
    expect(calls, 2);
  });
}
