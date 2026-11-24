import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viyo/screens/studio/novel_chapters.dart';

/// A fake server for the chapter screens: chapter 1 approved, chapter 2 waiting for review, chapter 3 next.
class FakeChaptersApi extends ChaptersApi {
  FakeChaptersApi({this.writing});
  Map<String, dynamic>? writing;
  final calls = <String>[];
  bool approved2 = false;

  @override
  Future<Map<String, dynamic>> list(String storyId) async => {
        'chapters': [
          {'number': 1, 'title': 'The Hem', 'status': 'approved', 'words': 3100, 'issues': 0},
          {'number': 2, 'title': 'The Watch', 'status': approved2 ? 'approved' : 'draft', 'words': 2900, 'issues': 1},
          {'number': 3, 'title': 'The Box', 'status': 'planned'},
        ],
        'next': approved2 ? 3 : 2,
        'writing': writing,
        'price': 11,
      };

  @override
  Future<Map<String, dynamic>> chapter(String storyId, int n) async => {
        'chapter': {
          'number': n,
          'title': 'The Watch',
          'status': approved2 ? 'approved' : 'draft',
          'version': 2,
          'words': 2900,
          'text': 'Eric came back the next morning.',
          'extraction': {
            'issues': [
              {
                'rule': 'dead_character_active',
                'reason': 'Mama Grace is dead from chapter 1 but speaks here.',
                'quote': 'Mama Grace laughed'
              }
            ]
          },
        },
        'suggestions': {
          'facts': [
            {'id': 'f1', 'statement': 'Eric turns his gold watch.', 'quote': 'turning his gold watch', 'conflicts': []},
            {
              'id': 'f2',
              'statement': 'Amani is 19.',
              'quote': 'only nineteen',
              'conflicts': ['creator-locked']
            },
          ],
          'events': [],
          'threads': [],
        },
      };

  @override
  Future<Map<String, dynamic>> write(String storyId, int n, String note) async {
    calls.add('write:$n:$note');
    return {'job_id': 'j1'};
  }

  @override
  Future<Map<String, dynamic>> approve(String storyId, int n, int version, bool withSuggestions) async {
    calls.add('approve:$n:$version:$withSuggestions');
    approved2 = true;
    return {
      'approved_suggestions': 1,
      'skipped': [
        {'statement': 'Amani is 19.', 'reason': 'creator-locked'}
      ]
    };
  }

  @override
  Future<Map<String, dynamic>> decide(
      String storyId, Map<String, List<String>> approve, Map<String, List<String>> reject) async {
    calls.add('decide:${approve.values.expand((x) => x).join()}|${reject.values.expand((x) => x).join()}');
    return {'done': [], 'refused': []};
  }
}

Widget _wrap(Widget w) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: w)));

void main() {
  testWidgets('lists chapters in order with their state and offers only the next one', (t) async {
    final api = FakeChaptersApi();
    await t.pumpWidget(_wrap(NovelChaptersSection(storyId: 's1', api: api)));
    await t.pumpAndSettle();
    expect(find.text('Chapters · 2 of 3 written'), findsOneWidget);
    expect(find.textContaining('Approved · 3100 words'), findsOneWidget);
    expect(find.textContaining('Waiting for your review · 2900 words · 1 continuity problem'), findsOneWidget);
    // Chapter 2 is a draft waiting for review, so there's no "write" button until it's approved.
    expect(find.textContaining('Write chapter'), findsNothing);
  });

  testWidgets('shows a chapter being written', (t) async {
    final api = FakeChaptersApi(writing: {'chapter': 2, 'status': 'running'});
    await t.pumpWidget(_wrap(NovelChaptersSection(storyId: 's1', api: api, poll: const Duration(hours: 1))));
    await t.pump();
    await t.pump();
    expect(find.text('Writing chapter 2…'), findsOneWidget);
  });

  testWidgets('a chapter shows its problems and suggestions, and the creator decides', (t) async {
    final api = FakeChaptersApi();
    await t.pumpWidget(MaterialApp(home: NovelChapterScreen(storyId: 's1', number: 2, api: api)));
    await t.pumpAndSettle();
    expect(find.text('Continuity problems'), findsOneWidget);
    expect(find.textContaining('Mama Grace is dead from chapter 1'), findsOneWidget);
    expect(find.text('Eric came back the next morning.'), findsOneWidget);
    expect(find.text('Conflicts: creator-locked'), findsOneWidget);
    await t.tap(find.byTooltip('Keep').first);
    await t.pumpAndSettle();
    expect(api.calls.last, 'decide:f1|');
    await t.tap(find.byTooltip('Reject').last);
    await t.pumpAndSettle();
    expect(api.calls.last, 'decide:|f2');
    await t.ensureVisible(find.text('Approve chapter and suggestions'));
    await t.pumpAndSettle();
    await t.tap(find.text('Approve chapter and suggestions'));
    await t.pumpAndSettle();
    expect(api.calls.last, 'approve:2:2:true');
    expect(find.textContaining('1 skipped: they contradict facts you locked'), findsOneWidget);
  });

  testWidgets('a new version can be asked for with a note', (t) async {
    final api = FakeChaptersApi();
    await t.pumpWidget(MaterialApp(home: NovelChapterScreen(storyId: 's1', number: 2, api: api)));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'More tension at the end');
    await t.ensureVisible(find.text('Write a new version'));
    await t.pumpAndSettle();
    await t.tap(find.text('Write a new version'));
    await t.pumpAndSettle();
    expect(api.calls.last, 'write:2:More tension at the end');
  });
}
