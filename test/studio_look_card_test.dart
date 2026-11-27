import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viyo/screens/studio/studio_look_card.dart';

Map<String, dynamic> state({bool saved = false, bool applies = true, String light = 'low-key, hard side light'}) => {
      'saved': saved,
      'applies': applies,
      'note': applies ? 'Every picture and clip of this production gets this look.' : 'Save a look to use it.',
      'fields': ['lens', 'light', 'palette', 'avoid'],
      'labels': {'lens': 'Lens', 'light': 'Light', 'palette': 'Colour palette', 'avoid': 'Avoid'},
      'look': {
        'style': 'Kigali at night',
        'lens': '35mm-equivalent',
        'light': light,
        'palette': ['cold teal', 'sodium amber'],
        'avoid': ['flat light'],
        'source': saved ? 'creator' : 'default',
      },
    };

void main() {
  testWidgets('shows the proposed look and saves only what the creator changed', (t) async {
    t.view.physicalSize = const Size(390, 1600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    Map<String, dynamic>? sent;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: StudioLookCard(
            projectId: 'p1',
            load: (_) async => state(),
            save: (_, fields, {bool reset = false}) async {
              sent = fields;
              return state(saved: true, light: fields['light'] as String);
            },
          ),
        ),
      ),
    ));
    await t.pumpAndSettle();
    expect(find.text('Look of the film'), findsOneWidget);
    expect(find.text('Proposed'), findsOneWidget);
    expect(find.textContaining('cold teal, sodium amber'), findsOneWidget);
    expect(find.textContaining('Every picture and clip'), findsOneWidget);
    await t.tap(find.text('Edit look'));
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextField, 'low-key, hard side light'), 'candlelight');
    await t.tap(find.text('Save look'));
    await t.pumpAndSettle();
    expect(sent, {'light': 'candlelight'});
    expect(find.text('Yours'), findsOneWidget);
    expect(find.textContaining('candlelight'), findsOneWidget);
    expect(find.text('Use VIYO\'s proposal'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('a film started before the look bible says how to use one', (t) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(body: StudioLookCard(projectId: 'p1', load: (_) async => state(applies: false))),
    ));
    await t.pumpAndSettle();
    expect(find.text('Save a look to use it.'), findsOneWidget);
  });
}
