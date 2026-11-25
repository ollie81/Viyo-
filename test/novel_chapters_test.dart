import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viyo/screens/studio/novel_chapters.dart';
import 'package:viyo/services/creator_studio_service.dart';

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
          'review': 'passed',
          'revised': true,
          'review_report': {
            'status': 'passed',
            'summary': "VIYO's review passed every area, each backed by words from the chapter.",
            'categories': {
              'emotion': {
                'status': 'verified',
                'score': 8,
                'reason': 'Earned through gesture.',
                'quote': 'her hands would not stop shaking'
              },
              'originality': {'status': 'unverified', 'score': 9, 'why': "Its quote isn't in the chapter."},
            },
            'weak': [],
            'revision': {
              'kept': true,
              'passages': [2],
              'why': 'every targeted area improved and nothing else got worse'
            },
          },
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
        'problems': [
          {
            'id': 'p1',
            'source': 'claim',
            'rule': 'dead_character_active',
            'reason': 'Mama Grace is dead from chapter 1 but speaks here.',
            'quote': 'Mama Grace laughed',
            'memory_statement': 'Mama Grace is dead.',
            'memory_locked': false,
            'judgement': {'verdict': 'error', 'why': 'Nothing marks it as a memory.', 'quote': ''},
            'actions': ['fix_chapter', 'chapter_right', 'intended'],
            if (resolution != null) 'resolution': resolution,
          }
        ],
        'fix_note': resolution?['action'] == 'fix_chapter' ? 'Fix these continuity problems: Mama Grace is dead.' : '',
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

  bool openProblems = false;
  Map<String, dynamic>? resolution;

  @override
  Future<Map<String, dynamic>> approve(String storyId, int n, int version, bool withSuggestions,
      {bool acceptProblems = false}) async {
    calls.add('approve:$n:$version:$withSuggestions${acceptProblems ? ':accept' : ''}');
    if (openProblems && !acceptProblems) {
      throw StudioException('1 continuity problem(s) need a decision first.', 409)..code = 'open_problems';
    }
    approved2 = true;
    return {
      'approved_suggestions': 1,
      'skipped': [
        {'statement': 'Amani is 19.', 'reason': 'creator-locked'}
      ]
    };
  }

  @override
  Future<Map<String, dynamic>> decideProblem(String storyId, int n, int version, String problemId, String action,
      {String reason = '', bool untilEnd = false, bool unlock = false}) async {
    calls.add('problem:$problemId:$action:$reason:$untilEnd');
    resolution = {'action': action};
    return {'summary': {}, 'fix_note': ''};
  }

  @override
  Future<Map<String, dynamic>> decide(
      String storyId, Map<String, List<String>> approve, Map<String, List<String>> reject) async {
    calls.add('decide:${approve.values.expand((x) => x).join()}|${reject.values.expand((x) => x).join()}');
    return {'done': [], 'refused': []};
  }
}

void tall(WidgetTester t) {
  t.view.physicalSize = const Size(1200, 6000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
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
    tall(t);
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
    await t.scrollUntilVisible(find.text('Approve chapter and suggestions'), 300,
        scrollable: find.byType(Scrollable).first);
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
    await t.scrollUntilVisible(find.byType(TextField), 300, scrollable: find.byType(Scrollable).first);
    await t.enterText(find.byType(TextField), 'More tension at the end');
    await t.ensureVisible(find.text('Write a new version'));
    await t.pumpAndSettle();
    await t.tap(find.text('Write a new version'));
    await t.pumpAndSettle();
    expect(api.calls.last, 'write:2:More tension at the end');
  });

  testWidgets("shows VIYO's review with verified scores, quotes and the revision outcome", (t) async {
    final api = FakeChaptersApi();
    await t.pumpWidget(MaterialApp(home: NovelChapterScreen(storyId: 's1', number: 2, api: api)));
    await t.pumpAndSettle();
    expect(find.text("VIYO's review"), findsOneWidget);
    await t.tap(find.text("VIYO's review"));
    await t.pumpAndSettle();
    expect(find.textContaining('Emotional depth: 8/10 — Earned through gesture.'), findsOneWidget);
    expect(find.textContaining('her hands would not stop shaking'), findsOneWidget);
    expect(find.textContaining("Originality: not counted (Its quote isn't in the chapter.)"), findsOneWidget);
    expect(find.textContaining('VIYO rewrote passage 2 and kept it'), findsOneWidget);
  });

  test('review labels for the chapter list', () {
    expect(reviewLabel('passed', true), 'review passed after a revision');
    expect(reviewLabel('needs_work', false), 'review: needs work');
    expect(reviewLabel('', false), '');
  });

  testWidgets("each continuity problem shows VIYO's opinion and the creator's choices", (t) async {
    tall(t);
    final api = FakeChaptersApi();
    await t.pumpWidget(MaterialApp(home: NovelChapterScreen(storyId: 's1', number: 2, api: api)));
    await t.pumpAndSettle();
    expect(find.text('VIYO thinks this is a mistake'), findsOneWidget);
    expect(find.text('The memory: Mama Grace is dead.'), findsOneWidget);
    expect(find.text('Fix the chapter'), findsOneWidget);
    expect(find.text('The chapter is right'), findsOneWidget);
    expect(find.text("It's intentional"), findsOneWidget);
    await t.tap(find.text('Fix the chapter'));
    await t.pumpAndSettle();
    expect(api.calls.last, 'problem:p1:fix_chapter::false');
    expect(find.text('✓ To fix in a new version'), findsOneWidget);
    // The fix note is ready for the next version.
    final field = t.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, contains('Mama Grace is dead'));
  });

  testWidgets('marking a problem intentional asks why', (t) async {
    tall(t);
    final api = FakeChaptersApi();
    await t.pumpWidget(MaterialApp(home: NovelChapterScreen(storyId: 's1', number: 2, api: api)));
    await t.pumpAndSettle();
    await t.tap(find.text("It's intentional"));
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextField, 'Why? (e.g. her ghost visits Amani)'), 'Her ghost');
    await t.tap(find.byType(CheckboxListTile));
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(api.calls.last, 'problem:p1:intended:Her ghost:true');
  });

  testWidgets('approving with open problems asks before approving anyway', (t) async {
    final api = FakeChaptersApi()..openProblems = true;
    await t.pumpWidget(MaterialApp(home: NovelChapterScreen(storyId: 's1', number: 2, api: api)));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.text('Approve chapter only'), 300, scrollable: find.byType(Scrollable).first);
    await t.ensureVisible(find.text('Approve chapter only'));
    await t.pumpAndSettle();
    await t.tap(find.text('Approve chapter only'));
    await t.pumpAndSettle();
    expect(find.text('Approve anyway?'), findsOneWidget);
    await t.tap(find.text('Yes'));
    await t.pumpAndSettle();
    expect(api.calls.last, 'approve:2:2:false:accept');
  });
}
