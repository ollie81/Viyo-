import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viyo/widgets/web_ad_card.dart';

void main() {
  tearDown(() => WebAdsConfig.override = null);

  test('config: on only with the switch and real ids', () {
    expect(WebAdsConfig.fromJson({'enabled': true, 'client': 'ca-pub-4161816109605295', 'slot': '6118261645'}).enabled,
        isTrue);
    expect(WebAdsConfig.fromJson({'enabled': false, 'client': 'ca-pub-1', 'slot': '1'}).enabled, isFalse);
    expect(WebAdsConfig.fromJson({'enabled': true, 'client': null, 'slot': null}).enabled, isFalse);
    expect(WebAdsConfig.fromJson({}).enabled, isFalse);
  });

  testWidgets('off the web (Android, iOS) the ad card is empty even when switched on', (t) async {
    WebAdsConfig.override = () async =>
        const WebAdsConfig(enabled: true, client: 'ca-pub-4161816109605295', slot: '6118261645');
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: Column(children: [WebAdCard(placement: 'home')]))));
    await t.pump(const Duration(seconds: 1));
    expect(find.text('Advertisement'), findsNothing);
    expect(find.byType(HtmlElementView), findsNothing);
  });

  test('outside the web the config is off without asking the server', () async {
    expect((await WebAdsConfig.get()).enabled, isFalse);
  });
}
