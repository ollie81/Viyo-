import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viyo/screens/studio/episode_plan_screen.dart';
import 'package:viyo/screens/studio/feature_screen.dart';
import 'package:viyo/screens/studio/novel_chapters.dart';

Map<String, dynamic> overview({bool ready = false, bool film = false}) => {
      'id': 'f1',
      'master_id': 'm1',
      'title': 'The Dress',
      'parts': [
        {'part': 1, 'project_id': 'p1', 'title': 'The Dress · Part 1: The letter', 'rendered': true, 'seconds': 598,
         'credits_to_finish': 0},
        {'part': 2, 'project_id': 'p2', 'title': 'The Dress · Part 2: The shop', 'rendered': ready, 'seconds': ready ? 600 : null,
         'credits_to_finish': ready ? 0 : 6400},
        {'part': 3, 'project_id': 'p3', 'title': 'The Dress · Part 3: The truth', 'rendered': ready, 'seconds': ready ? 590 : null,
         'credits_to_finish': ready ? 0 : 6300},
      ],
      'credits_to_finish': ready ? 0 : 12700,
      'ready_to_join': ready,
      'missing': ready ? [] : [2, 3],
      'film': film ? {'version': 1, 'duration_seconds': 1788.0} : null,
      'note': 'Each part is made like one production.',
    };

Future<void> pump(WidgetTester t, Widget w) async {
  t.view.physicalSize = const Size(390, 1600);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(home: w));
  await t.pumpAndSettle();
}

class FakeApi extends ChaptersApi {
  final calls = <String>[];
  @override
  Future<Map<String, dynamic>> episodes(String storyId) async =>
      {'plan': [], 'problems': [], 'version': 0, 'seconds': 90, 'episodes_wanted': 0, 'created': [], 'format': 'episodes',
       'price': 40};
  @override
  Future<Map<String, dynamic>> planFeature(String storyId, int minutes, String note) async {
    calls.add('feature $minutes');
    return {'format': 'feature', 'feature_minutes': minutes, 'plan': [], 'problems': []};
  }
}

void main() {
  testWidgets('parts not rendered yet: the join waits and says which', (t) async {
    await pump(t, FeatureScreen(featureId: 'f1', load: (_) async => overview()));
    expect(find.text('1 of 3 parts rendered'), findsOneWidget);
    expect(find.text('Rendered · 598 s'), findsOneWidget);
    expect(find.textContaining('Not rendered yet · about 6,400 credits'), findsOneWidget);
    expect(find.text('Render parts 2, 3 first.'), findsOneWidget);
    final join = t.widget<FilledButton>(find.ancestor(of: find.text('Join the movie'), matching: find.byWidgetPredicate((w) => w is FilledButton)));
    expect(join.onPressed, isNull);
    expect(t.takeException(), isNull);
  });

  testWidgets('every part rendered: join, then the movie is shown', (t) async {
    var joined = 0;
    var film = false;
    await pump(
        t,
        FeatureScreen(
          featureId: 'f1',
          load: (_) async => overview(ready: true, film: film),
          join: (_, id) async {
            joined++;
            film = true;
            return id == 'm1';
          },
        ));
    await t.tap(find.text('Join the movie'));
    await t.pumpAndSettle();
    expect(joined, 1);
    expect(find.textContaining('The movie is joined: version 1, 29.8 minutes'), findsOneWidget);
    expect(find.text('Join again'), findsOneWidget);
  });

  testWidgets('the plan screen offers a feature film and plans it by length', (t) async {
    final api = FakeApi();
    await pump(t, EpisodePlanScreen(storyId: 's1', api: api));
    await t.tap(find.text('Feature film'));
    await t.pumpAndSettle();
    expect(find.textContaining('3 parts of about 10 minutes'), findsOneWidget);
    await t.enterText(find.widgetWithText(TextField, '30'), '60');
    await t.pumpAndSettle();
    await t.tap(find.textContaining('Plan the movie'));
    await t.pumpAndSettle();
    expect(api.calls, ['feature 60']);
  });
}
