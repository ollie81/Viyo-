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
  final started = <(String, String)>[];
  final asked = <String>[];

  @override
  Future<Donation> start(String creatorId, String message) async {
    started.add((creatorId, message));
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

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the donor writes a message; the server is asked for a donation to that creator (no amount)', (t) async {
    final api = FakeDonations();
    await t.pumpWidget(MaterialApp(
        theme: ThemeData.dark(), home: DonateScreen(creatorId: 'c1', creatorName: 'Amani', api: api)));
    await settle(t);
    expect(find.text('Support Amani'), findsOneWidget);
    expect(find.textContaining('80% goes to the creator'), findsOneWidget);
    expect(find.textContaining('not coins'), findsOneWidget);
    await t.enterText(find.byType(TextField), 'Love your drama!');
    await t.tap(find.text('Continue to payment'));
    await settle(t);
    expect(api.started, [('c1', 'Love your drama!')]);
    expect(find.text('Donation not completed'), findsOneWidget);
    expect(find.text('test stop'), findsOneWidget);
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
    await t.pump(const Duration(seconds: 5));          // next check: paid
    await t.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('Thank you!'), findsOneWidget);
    await t.pump(const Duration(seconds: 2));
    await t.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);           // closed after the thank-you
    expect(api.asked, ['d-9', 'd-9']);
    expect(await PendingPurchase.peek(), isNull);
    await t.pump(const Duration(seconds: 4));
  });

  test('a donation in progress is remembered like a purchase', () async {
    await PendingPurchase.save('donation', 'd-1');
    expect((await PendingPurchase.peekKind('donation'))!.id, 'd-1');
  });
}
