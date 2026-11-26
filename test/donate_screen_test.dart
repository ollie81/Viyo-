import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:viyo/screens/wallet/donate_screen.dart';
import 'package:viyo/services/donation_service.dart';
import 'package:viyo/services/pending_purchase.dart';

/// Records what the server is asked; start() stops before any browser tab would open.
class FakeDonations extends DonationApi {
  FakeDonations({this.statuses = const ['pending']});
  final List<String> statuses;
  final started = <(String, String, int)>[];
  final asked = <String>[];

  @override
  Future<DonationOptions> options() async => const DonationOptions(available: true, feePercent: 17);

  @override
  Future<Donation> start(String creatorId, String message, int usdCents) async {
    started.add((creatorId, message, usdCents));
    throw Exception('test stop');
  }

  @override
  Future<Donation> status(String donationId) async {
    asked.add(donationId);
    final s = statuses[asked.length - 1 < statuses.length ? asked.length - 1 : statuses.length - 1];
    return Donation(id: donationId, status: s, creatorId: 'c1');
  }
}

Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 10; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> tapText(WidgetTester t, String text) async {
  await t.ensureVisible(find.text(text));
  await t.pump();
  await t.tap(find.text(text));
  await settle(t);
}

Future<FakeDonations> open(WidgetTester t) async {
  final api = FakeDonations();
  t.view.physicalSize = const Size(390, 1400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
      theme: ThemeData.dark(), home: DonateScreen(creatorId: 'c1', creatorName: 'Amani', api: api)));
  await settle(t);
  return api;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the donor picks a dollar amount (never francs) and sees the fee; the server gets cents', (t) async {
    final api = await open(t);
    expect(find.text('Support Amani'), findsOneWidget);
    expect(find.textContaining('80% goes to the creator'), findsOneWidget);
    expect(find.textContaining('RWF'), findsNothing);
    expect(find.text(r'Donate $5 + fee'), findsOneWidget);             // $5 preselected
    await tapText(t, r'$10');
    expect(find.text(r'Donate $10 + fee'), findsOneWidget);
    expect(find.text(r'$10 + about $1.70 NardoPay fee'), findsOneWidget);
    await t.enterText(find.byType(TextField).last, 'Love your drama!');
    await tapText(t, r'Donate $10 + fee');
    expect(api.started, [('c1', 'Love your drama!', 1000)]);
    expect(find.text('test stop'), findsOneWidget);
  });

  testWidgets('a custom amount must be between \$1 and \$500', (t) async {
    final api = await open(t);
    await tapText(t, 'Other');
    await t.enterText(find.byType(TextField).first, '0.50');
    await settle(t);
    expect(find.text('Choose an amount'), findsOneWidget);
    await t.enterText(find.byType(TextField).first, '7.5');
    await settle(t);
    expect(find.text(r'Donate $7.50 + fee'), findsOneWidget);
    await tapText(t, r'Donate $7.50 + fee');
    expect(api.started.single.$3, 750);
  });

  testWidgets('back from NardoPay: it keeps checking until the server confirms, then thanks the donor', (t) async {
    await PendingPurchase.save('donation', 'd-9');
    final api = FakeDonations(statuses: ['pending', 'paid']);
    await t.pumpWidget(MaterialApp(
      theme: ThemeData.dark(),
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => DonateScreen(
                  creatorId: '', creatorName: 'the creator', resumeDonationId: 'd-9', api: api))),
          child: const Text('open'),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    await settle(t);
    expect(find.text('Waiting for payment confirmation'), findsOneWidget);
    await t.pump(const Duration(seconds: 5));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('Thank you!'), findsOneWidget);
    await t.pump(const Duration(seconds: 2));
    await t.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
    expect(await PendingPurchase.peek(), isNull);
    await t.pump(const Duration(seconds: 4));
  });
}
