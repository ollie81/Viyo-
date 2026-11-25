import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viyo/screens/admin/nardopay_test_screen.dart';

void main() {
  testWidgets('the admin creates a test link and sees where NardoPay put it', (t) async {
    String? key;
    int? amount;
    await t.pumpWidget(MaterialApp(
        home: NardopayTestScreen(call: (k, a) async {
      key = k;
      amount = a;
      return {
        'link': 'https://pay.example/l/xyz',
        'links_found': [
          {'field': 'data.payment_url', 'url': 'https://pay.example/l/xyz'}
        ],
        'amount_sent': 100,
      };
    })));
    await t.enterText(find.widgetWithText(TextField, 'Admin key'), 'secret');
    await t.tap(find.text('Create test link'));
    await t.pumpAndSettle();
    expect(key, 'secret');
    expect(amount, 100);
    expect(find.text('https://pay.example/l/xyz'), findsOneWidget);
    expect(find.text('data.payment_url'), findsOneWidget);
  });

  testWidgets('it asks for the admin key and a sensible amount, and shows server errors', (t) async {
    await t.pumpWidget(MaterialApp(home: NardopayTestScreen(call: (k, a) async => throw Exception('Set these first'))));
    await t.tap(find.text('Create test link'));
    await t.pump();
    expect(find.textContaining('Enter the admin key'), findsOneWidget);
    await t.enterText(find.widgetWithText(TextField, 'Admin key'), 'secret');
    await t.tap(find.text('Create test link'));
    await t.pumpAndSettle();
    expect(find.text('Set these first'), findsOneWidget);
  });
}
