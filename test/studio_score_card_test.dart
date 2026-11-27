import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viyo/screens/studio/studio_score_card.dart';

Map<String, dynamic> sheet({String uses = 'planned score', bool enabled = true}) => {
      'enabled': enabled,
      'uses': uses,
      'new_cues': 3,
      'music_credits': 33,
      'themes': {'Maya': 'a bold brass call of three rising notes'},
      'cues': [
        {'mood': 'tension', 'positions': [1, 2], 'seconds': 16, 'silent': false, 'status': 'made'},
        {'mood': 'action', 'positions': [3], 'seconds': 12, 'silent': false, 'status': 'new'},
        {'mood': 'silence', 'positions': [4], 'seconds': 6, 'silent': true, 'status': 'silent'},
      ],
      'note': 'Cues that haven\'t changed are reused for free.',
    };

void main() {
  testWidgets('shows each cue, planned silences, themes and what new cues cost', (t) async {
    t.view.physicalSize = const Size(390, 1200);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(home: Scaffold(body: StudioScoreCard(projectId: 'p', load: (_) async => sheet()))));
    await t.pumpAndSettle();
    expect(find.text('Score'), findsOneWidget);
    expect(find.text('3 new · 33 credits'), findsOneWidget);
    expect(find.text('Scenes 1, 2 · 16 s · made'), findsOneWidget);
    expect(find.text('Scene 3 · 12 s · new'), findsOneWidget);
    expect(find.text('Scene 4 · 6 s · planned silence'), findsOneWidget);
    expect(find.textContaining('Maya\'s theme: a bold brass call'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('own music or music off says so', (t) async {
    await t.pumpWidget(MaterialApp(
        home: Scaffold(body: StudioScoreCard(projectId: 'p', load: (_) async => sheet(uses: 'your music', enabled: false)))));
    await t.pumpAndSettle();
    expect(find.text('Your own music plays under the film.'), findsOneWidget);
  });
}
