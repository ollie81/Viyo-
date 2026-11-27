import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viyo/screens/studio/studio_film_report.dart';

const report = {
  'status': 'problems',
  'summary': '3 things to look at, 1 serious: duplicated shots (1), missing shots (1), camera variety (1).',
  'render': {'version': 2, 'duration_seconds': 61.0},
  'categories': [
    {'key': 'duplicates', 'label': 'Duplicated shots', 'status': 'attention', 'count': 1},
    {'key': 'missing', 'label': 'Missing shots', 'status': 'problem', 'count': 1},
    {'key': 'camera', 'label': 'Camera variety', 'status': 'attention', 'count': 1},
    {'key': 'pacing', 'label': 'Pacing', 'status': 'ok', 'count': 0},
  ],
  'problems': [
    {'category': 'missing', 'severity': 'high', 'scene': 4, 'shot': 2, 'problem': 'Scene 4, shot 2 has no picture yet.',
     'fix': 'Make it before the film is rendered.', 'route': 'remake', 'route_label': 'Paid remake (price shown first)'},
    {'category': 'duplicates', 'severity': 'medium', 'scene': 9, 'shot': 1,
     'problem': 'Scene 9, shot 1 looks almost identical to Scene 2, shot 1.', 'fix': 'Change the framing.',
     'route': 'remake', 'route_label': 'Paid remake (price shown first)'},
    {'category': 'camera', 'severity': 'medium', 'scene': null, 'shot': null,
     'problem': '74% of the shots are establishing wides.', 'fix': 'Mix in other sizes.', 'route': 'edit',
     'route_label': 'Free edit'},
  ],
  'notes': ['2 shot picture(s) haven\'t been checked against the references.'],
  'note': 'This report is free and changes nothing.',
};

void main() {
  for (final width in [390.0, 1280.0]) {
    testWidgets('shows every problem with where it is, the fix and the route (width $width)', (t) async {
      t.view.physicalSize = Size(width, 2400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(theme: ThemeData.dark(), home: const Scaffold(body: FilmReportView(report: report))));
      expect(find.text('Version 2 of your film.'), findsOneWidget);
      expect(find.textContaining('3 things to look at'), findsOneWidget);
      expect(find.text('Scene 4, shot 2'), findsOneWidget);
      expect(find.text('Whole film'), findsOneWidget);
      expect(find.text('Fix: Make it before the film is rendered.'), findsOneWidget);
      expect(find.text('Paid remake (price shown first)'), findsNWidgets(2));
      expect(find.text('Free edit'), findsOneWidget);
      expect(find.text('Pacing · OK'), findsOneWidget);
      expect(find.textContaining('changes nothing'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('a category chip filters the list', (t) async {
    t.view.physicalSize = const Size(390, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: FilmReportView(report: report))));
    await t.tap(find.text('Camera variety · 1'));
    await t.pump();
    expect(find.text('74% of the shots are establishing wides.'), findsOneWidget);
    expect(find.text('Scene 4, shot 2 has no picture yet.'), findsNothing);
    await t.tap(find.text('Pacing · OK'));
    await t.pump();
    expect(find.text('Nothing to fix here.'), findsOneWidget);
  });
}
