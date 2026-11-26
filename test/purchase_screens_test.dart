import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viyo/screens/wallet/buy_coins_screen.dart';
import 'package:viyo/screens/wallet/subscribe_screen.dart';
import 'package:viyo/services/checkout_options_service.dart';
import 'package:viyo/services/coin_purchase_service.dart';
import 'package:viyo/services/nardopay_service.dart';
import 'package:viyo/services/subscription_service.dart';

/// Records which plan the server was asked to subscribe, then stops before any browser tab would open.
class RecordingPremium extends PremiumCheckoutApi {
  RecordingPremium();
  final plans = <String>[];

  @override
  Future<PremiumSubscription> create(String plan) async {
    plans.add(plan);
    throw Exception('test stop');
  }
}

final packages = [
  CoinPackage(id: 'starter', coins: 100, usdCents: 99, label: '100 Coins'),
  CoinPackage(id: 'popular', coins: 550, usdCents: 499, label: '550 Coins'),
  CoinPackage(id: 'value', coins: 1200, usdCents: 999, label: '1,200 Coins'),
  CoinPackage(id: 'creator', coins: 3000, usdCents: 1999, label: '3,000 Coins'),
];

const closedPlans = [
  PremiumPlan(plan: 'weekly', available: false, reason: "Premium subscriptions aren't open yet."),
  PremiumPlan(plan: 'monthly', available: false, reason: "Premium subscriptions aren't open yet."),
  PremiumPlan(plan: 'yearly', available: false, reason: "Premium subscriptions aren't open yet."),
];

const openPlans = [
  PremiumPlan(plan: 'weekly', available: true, priceCents: 199, currency: 'USD', interval: 'week', intervalCount: 1),
  PremiumPlan(plan: 'monthly', available: true, priceCents: 599, currency: 'USD', interval: 'month', intervalCount: 1),
  PremiumPlan(plan: 'yearly', available: true, priceCents: 4999, currency: 'USD', interval: 'year', intervalCount: 1),
];

CheckoutOptions options({List<String> providers = const [], List<PremiumPlan> plans = closedPlans}) =>
    CheckoutOptions(coinProviders: providers, packages: packages, premiumPlans: plans);

/// Records which package NardoPay was asked to charge, then fails before any browser tab would open.
class RecordingNardopay extends NardopayApi {
  RecordingNardopay();
  final created = <String>[];

  @override
  Future<NardopayOrder> create(String packageId) async {
    created.add(packageId);
    throw Exception('test stop');
  }
}

const phone = Size(390, 844);
const desktop = Size(1280, 900);

Future<void> show(WidgetTester t, Widget screen, Size size) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(theme: ThemeData.dark(), home: screen));
  await t.pumpAndSettle();
}

Future<void> tapText(WidgetTester t, String text) async {
  await t.ensureVisible(find.text(text));
  await t.pumpAndSettle();
  await t.tap(find.text(text));
  await t.pumpAndSettle();
}

ElevatedButton primary(WidgetTester t) => t.widget<ElevatedButton>(find.byType(ElevatedButton).last);

void main() {
  group('payment methods per platform', () {
    test('Android sells nothing, the web never shows Stripe, NardoPay is web-only, Lemon Squeezy never', () {
      const live = ['stripe', 'paystack', 'flutterwave', 'lemonsqueezy', 'nardopay'];
      expect(coinMethodsFor(PurchasePlatform.android, live), isEmpty);
      expect(coinMethodsFor(PurchasePlatform.web, live), ['paystack', 'flutterwave', 'nardopay']);
      expect(coinMethodsFor(PurchasePlatform.other, live), ['stripe', 'paystack', 'flutterwave']);
      expect(coinMethodsFor(PurchasePlatform.web, const []), isEmpty);
    });

    test('options are read from the server answer; a plan without a price is never purchasable', () {
      final o = CheckoutOptions.fromJson({
        'coins': {
          'providers': ['nardopay'],
          'packages': [
            {'id': 'starter', 'coins': 100, 'usd_cents': 99, 'label': '100 Coins'}
          ]
        },
        'premium': {
          'plans': [
            {'plan': 'monthly', 'available': true, 'price_cents': 599, 'currency': 'USD', 'interval': 'month'},
            {'plan': 'yearly', 'available': true, 'price_cents': null},
          ]
        },
      });
      expect(o.coinProviders, ['nardopay']);
      expect(o.packages.single.priceDisplay, r'$0.99');
      expect(o.premiumPlans[0].priceLabel, r'$5.99');
      expect(o.premiumPlans[1].available, isFalse);
      expect(o.premiumPlans[1].priceLabel, isNull);
    });
  });

  group('Buy Coins', () {
    for (final size in [phone, desktop]) {
      testWidgets('with no live method: real prices, an honest notice, no fake option (${size.width})', (t) async {
        await show(t, BuyCoinsScreen(loadOptions: () async => options(), platform: PurchasePlatform.web), size);
        for (final price in [r'$0.99', r'$4.99', r'$9.99', r'$19.99']) {
          expect(find.text(price), findsOneWidget);
        }
        expect(find.text("Buying coins isn't available right now"), findsOneWidget);
        for (final name in ['Stripe', 'Paystack', 'Flutterwave', 'Lemon Squeezy', 'NardoPay']) {
          expect(find.textContaining(name), findsNothing);
        }
        expect(find.text('Purchases not available'), findsOneWidget);
        expect(primary(t).onPressed, isNull);
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('only live methods this platform can run are listed', (t) async {
      await show(
          t,
          BuyCoinsScreen(
              loadOptions: () async => options(providers: ['stripe', 'paystack', 'nardopay']),
              platform: PurchasePlatform.web),
          phone);
      expect(find.text('Card'), findsOneWidget);
      expect(find.text('Paystack'), findsOneWidget);
      expect(find.textContaining('Stripe'), findsNothing); // not runnable on the web
    });

    testWidgets('choosing a package updates the pay button, and Pay goes to the NardoPay checkout for it', (t) async {
      final nardopay = RecordingNardopay();
      await show(
          t,
          BuyCoinsScreen(
              loadOptions: () async => options(providers: ['nardopay']),
              platform: PurchasePlatform.web,
              nardopay: nardopay),
          desktop);
      expect(find.text(r'Pay $0.99'), findsOneWidget); // first package selected by default
      await tapText(t, '550');
      expect(find.text(r'Pay $4.99'), findsOneWidget);
      expect(find.text('+9% coins'), findsOneWidget); // 550/$4.99 vs 100/$0.99 = +9%, from the real prices
      await t.tap(find.text(r'Pay $4.99'));
      await t.pumpAndSettle();
      expect(nardopay.created, ['popular']);
      expect(find.text('Payment not completed'), findsOneWidget);
      expect(find.text('test stop'), findsOneWidget);
    });

    testWidgets('a load failure shows a retry, not an empty screen', (t) async {
      var calls = 0;
      await show(
          t,
          BuyCoinsScreen(
              loadOptions: () async {
                calls++;
                if (calls == 1) throw Exception('offline');
                return options();
              },
              platform: PurchasePlatform.web),
          phone);
      expect(find.text("Coin packages couldn't be loaded"), findsOneWidget);
      await t.tap(find.text('Try again'));
      await t.pumpAndSettle();
      expect(find.text(r'$4.99'), findsOneWidget);
    });

    testWidgets('Android offers no purchase at all (Google Play)', (t) async {
      await show(t, BuyCoinsScreen(loadOptions: () async => options(providers: ['nardopay']),
          platform: PurchasePlatform.android), phone);
      expect(find.text("Buying coins isn't available here yet"), findsOneWidget);
      expect(find.text(r'$0.99'), findsNothing);
    });
  });

  group('Premium', () {
    Future<SubscriptionStatus> notSubscribed() async => SubscriptionStatus(isSubscribed: false);

    for (final size in [phone, desktop]) {
      testWidgets('not open yet: no invented prices, clear reason, disabled button (${size.width})', (t) async {
        await show(
            t,
            SubscribeScreen(
                loadOptions: () async => options(), loadStatus: notSubscribed, platform: PurchasePlatform.web),
            size);
        expect(find.text("Premium subscriptions aren't open yet"), findsOneWidget);
        expect(find.text('Not available'), findsNWidgets(3));
        expect(find.textContaining(r'$'), findsNothing);
        expect(find.text('Not available yet'), findsOneWidget);
        expect(primary(t).onPressed, isNull);
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('real prices, monthly selected by default, yearly saving computed from them', (t) async {
      await show(
          t,
          SubscribeScreen(
              loadOptions: () async => options(plans: openPlans),
              loadStatus: notSubscribed,
              platform: PurchasePlatform.web),
          phone);
      expect(find.text(r'$1.99'), findsOneWidget);
      expect(find.text(r'$5.99'), findsOneWidget);
      expect(find.text(r'$49.99'), findsOneWidget);
      expect(find.text('Save 30%'), findsOneWidget); // 49.99 vs 12 x 5.99 = 71.88
      expect(find.text(r'Subscribe · $5.99 / month'), findsOneWidget);
      await tapText(t, 'Yearly');
      expect(find.text(r'Subscribe · $49.99 / year'), findsOneWidget);
      expect(find.textContaining('not coins'), findsOneWidget);
    });

    testWidgets('a plan without a price stays unselectable while the others work', (t) async {
      await show(
          t,
          SubscribeScreen(
              loadOptions: () async => options(plans: [
                    closedPlans[0],
                    openPlans[1],
                    closedPlans[2],
                  ]),
              loadStatus: notSubscribed,
              platform: PurchasePlatform.web),
          phone);
      await tapText(t, 'Weekly');
      expect(find.text(r'Subscribe · $5.99 / month'), findsOneWidget);
    });

    testWidgets('a member sees their plan, not a sales page', (t) async {
      await show(
          t,
          SubscribeScreen(
              loadStatus: () async => SubscriptionStatus(
                  isSubscribed: true, plan: 'monthly', provider: 'lemonsqueezy', renewsAt: '2026-12-25T00:00:00Z'),
              platform: PurchasePlatform.web),
          desktop);
      expect(find.text("You're a Premium member"), findsOneWidget);
      expect(find.text('Renews 2026-12-25'), findsOneWidget);
      expect(find.text('Active'), findsOneWidget);
    });

    testWidgets('Android does not offer Premium', (t) async {
      await show(
          t,
          SubscribeScreen(
              loadOptions: () async => options(plans: openPlans),
              loadStatus: notSubscribed,
              platform: PurchasePlatform.android),
          phone);
      expect(find.text("Premium isn't available in this app"), findsOneWidget);
      expect(find.byType(ElevatedButton), findsNothing);
    });

    testWidgets('Subscribe asks the server for this viewer\'s own NardoPay subscription for the chosen plan',
        (t) async {
      final premium = RecordingPremium();
      await show(
          t,
          SubscribeScreen(
              loadOptions: () async => options(plans: openPlans),
              loadStatus: notSubscribed,
              platform: PurchasePlatform.web,
              checkout: premium),
          phone);
      expect(find.textContaining('Pay by debit or credit card'), findsOneWidget);
      expect(find.textContaining('Lemon Squeezy'), findsNothing);
      await tapText(t, 'Yearly');
      await t.ensureVisible(find.text(r'Subscribe · $49.99 / year'));
      await t.tap(find.text(r'Subscribe · $49.99 / year'));
      await t.pumpAndSettle();
      expect(premium.plans, ['yearly']);
      expect(find.text('test stop'), findsOneWidget);
      expect(find.text('Waiting for payment confirmation'), findsNothing); // nothing to wait for without a link
    });

    testWidgets('a NardoPay member sees the next payment date and how to stop', (t) async {
      await show(
          t,
          SubscribeScreen(
              loadStatus: () async => SubscriptionStatus(
                  isSubscribed: true, plan: 'weekly', provider: 'nardopay', renewsAt: '2026-12-03T10:00:00Z'),
              platform: PurchasePlatform.web),
          phone);
      expect(find.text('Weekly plan'), findsOneWidget);
      expect(find.text('Next payment due 2026-12-03'), findsOneWidget);
      expect(find.textContaining('cancel it with NardoPay'), findsOneWidget);
    });

    testWidgets('the native apps never offer Premium', (t) async {
      await show(
          t,
          SubscribeScreen(
              loadOptions: () async => options(plans: openPlans),
              loadStatus: notSubscribed,
              platform: PurchasePlatform.other),
          phone);
      expect(find.text("Premium isn't available in this app"), findsOneWidget);
      expect(find.byType(ElevatedButton), findsNothing);
    });
  });
}
