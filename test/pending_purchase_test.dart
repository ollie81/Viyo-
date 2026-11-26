import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:viyo/screens/wallet/subscribe_screen.dart';
import 'package:viyo/services/checkout_options_service.dart';
import 'package:viyo/services/pending_purchase.dart';
import 'package:viyo/services/subscription_service.dart';

/// Answers status checks with the given statuses in order (then repeats the last).
class FakePremium extends PremiumCheckoutApi {
  FakePremium(this.statuses);
  final List<String> statuses;
  final asked = <String>[];

  @override
  Future<PremiumSubscription> status(String id) async {
    asked.add(id);
    final s = statuses[asked.length - 1 < statuses.length ? asked.length - 1 : statuses.length - 1];
    return PremiumSubscription(id: id, status: s, plan: 'weekly');
  }
}

const plans = [
  PremiumPlan(plan: 'weekly', available: true, priceCents: 399, currency: 'USD', interval: 'week', intervalCount: 1),
];

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a saved purchase is remembered, by kind, and cleared', () async {
    expect(await PendingPurchase.peek(), isNull);
    await PendingPurchase.save('premium', 'sub-1');
    final p = await PendingPurchase.peek();
    expect(p!.kind, 'premium');
    expect(p.id, 'sub-1');
    expect(await PendingPurchase.peekKind('coins'), isNull);
    await PendingPurchase.clear();
    expect(await PendingPurchase.peek(), isNull);
  });

  test('an old or broken record is ignored and removed', () async {
    final old = DateTime.now().toUtc().subtract(const Duration(hours: 3)).toIso8601String();
    SharedPreferences.setMockInitialValues({'pending_nardopay_purchase': 'premium|sub-1|$old'});
    expect(await PendingPurchase.peek(), isNull);
    SharedPreferences.setMockInitialValues({'pending_nardopay_purchase': 'gift|x|nonsense'});
    expect(await PendingPurchase.peek(), isNull);
  });

  testWidgets('back from NardoPay: the Premium screen keeps checking until the server confirms', (t) async {
    await PendingPurchase.save('premium', 'sub-9');
    final api = FakePremium(['pending', 'active']);
    await t.pumpWidget(MaterialApp(
      theme: ThemeData.dark(),
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => SubscribeScreen(
                  loadOptions: () async => CheckoutOptions(coinProviders: const [], packages: const [], premiumPlans: plans),
                  loadStatus: () async => SubscriptionStatus(isSubscribed: false),
                  platform: PurchasePlatform.web,
                  checkout: api))),
          child: const Text('open'),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Waiting for payment confirmation'), findsOneWidget);
    expect(api.asked, ['sub-9']);
    await t.pump(const Duration(seconds: 5)); // next check: active
    await t.pumpAndSettle();
    expect(api.asked, ['sub-9', 'sub-9']);
    expect(find.text('open'), findsOneWidget); // the screen closed after confirmation
    expect(await PendingPurchase.peek(), isNull);
    await t.pump(const Duration(seconds: 4)); // the welcome message's timer runs out
  });

  testWidgets('"I didn\'t pay" stops waiting and forgets the purchase', (t) async {
    await PendingPurchase.save('premium', 'sub-7');
    await t.pumpWidget(MaterialApp(
      theme: ThemeData.dark(),
      home: SubscribeScreen(
          loadOptions: () async => CheckoutOptions(coinProviders: const [], packages: const [], premiumPlans: plans),
          loadStatus: () async => SubscriptionStatus(isSubscribed: false),
          platform: PurchasePlatform.web,
          checkout: FakePremium(['pending'])),
    ));
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    await t.ensureVisible(find.text("I didn't pay · Cancel"));
    await t.pump();
    await t.tap(find.text("I didn't pay · Cancel"));
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Waiting for payment confirmation'), findsNothing);
    expect(await PendingPurchase.peek(), isNull);
    await t.pump(const Duration(seconds: 5)); // the stopped check's last timer runs out and asks nothing more
  });
}
