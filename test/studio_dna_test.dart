import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viyo/screens/studio/studio_dna.dart';

const card = {
  'name': 'Maya',
  'locked': true,
  'look': {
    'identity': {
      'basic': {'age': 'late 20s', 'skin_tone': 'warm medium brown'},
      'face': {'hair': 'short black hair'},
      'default_outfit': 'red jacket',
    },
    'reference_views': [],
    'outfits': [
      {'name': 'Wedding', 'description': 'white kitenge dress'}
    ],
  },
  'voice': {'voice': 'Kore', 'description': 'warm, low', 'locked': true},
  'person': {'personality': 'brave, warm', 'description': 'A nurse'},
  'story': {'role': 'lead', 'arc': 'from fear to courage'},
  'relationships': [
    {'between': 'Maya and Daniel', 'kind': 'love', 'tension': 'his lie'}
  ],
  'emotional_state': {'emotion': 'hopeful', 'scene': 1},
  'appears_in_scenes': [1, 3],
  'consistency': {'shots': 6, 'checked': 4, 'flagged': 1},
  'look_alikes': [
    {'problem': 'Maya and Grace look alike: same hair.', 'fix': 'Give Grace a different hair colour.'}
  ],
};

void main() {
  testWidgets('the DNA card shows look, voice, story, relationships, state and look-alikes', (t) async {
    t.view.physicalSize = const Size(390, 2000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: CharacterDnaView(dna: card))));
    expect(find.text('Maya'), findsOneWidget);
    expect(find.text('Locked'), findsOneWidget);
    expect(find.text('late 20s · warm medium brown'), findsOneWidget);
    expect(find.text('Usually wears: red jacket'), findsOneWidget);
    expect(find.text('Outfit "Wedding": white kitenge dress'), findsOneWidget);
    expect(find.text('Kore (locked)'), findsOneWidget);
    expect(find.text('Arc: from fear to courage'), findsOneWidget);
    expect(find.text('Maya and Daniel: love (his lie)'), findsOneWidget);
    expect(find.text('Feeling hopeful (scene 1)'), findsOneWidget);
    expect(find.text('Pictures checked: 4 of 6 shots · 1 drawn differently'), findsOneWidget);
    expect(find.textContaining('Give Grace a different hair colour'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('the cast banner lists look-alikes and hides when there are none', (t) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CastCheckBanner(
          projectId: 'p',
          load: (_) async => {
            'pairs': [
              {'problem': 'Ama and Abena look alike: same hair, skin tone.', 'fix': 'Give Abena a different hair colour.'}
            ]
          },
        ),
      ),
    ));
    await t.pumpAndSettle();
    expect(find.text('Characters who look alike'), findsOneWidget);
    expect(find.textContaining('Give Abena a different hair colour'), findsOneWidget);
    await t.pumpWidget(MaterialApp(
        home: Scaffold(body: CastCheckBanner(projectId: 'q', load: (_) async => {'pairs': []}))));
    await t.pumpAndSettle();
    expect(find.text('Characters who look alike'), findsNothing);
  });
}
