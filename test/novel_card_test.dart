import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viyo/screens/studio/studio_novel_card.dart';

/// A fake server: records what the card asks for and returns the next story state.
class FakeNovelApi extends NovelApi {
  FakeNovelApi(this.story);
  Map<String, dynamic>? story;
  final calls = <String>[];

  @override
  Future<Map<String, dynamic>?> load(String projectId) async => story;
  @override
  Future<Map<String, dynamic>> start(String projectId, String idea, String length, int episodes) async {
    calls.add('start:$length:$episodes:$idea');
    return story = _interviewing(question: {
      'topic': 'goal',
      'text': 'What does she want most?',
      'options': ['Justice']
    });
  }

  @override
  Future<Map<String, dynamic>> interview(String storyId,
      {String? answer, bool skip = false, bool finish = false}) async {
    calls.add('interview:${answer ?? ''}:$skip:$finish');
    return story = _interviewing(ready: true);
  }

  @override
  Future<Map<String, dynamic>> outline(String storyId, String note) async {
    calls.add('outline:$note');
    return story = _outlined();
  }

  @override
  Future<Map<String, dynamic>> approve(String storyId, int version) async {
    calls.add('approve:$version');
    return {
      'story': {..._outlined(), 'stage': 'outline_approved'},
      'memory': {'entities': 6, 'facts': 20, 'threads': 2}
    };
  }
}

Map<String, dynamic> _interviewing({Map<String, dynamic>? question, bool ready = false}) => {
      'id': 's1',
      'idea': 'A seamstress finds a letter in a wedding dress.',
      'stage': 'interview',
      'interview': {
        'question': question,
        'ready': ready,
        'known': {
          'feeling': {'value': 'hopeful but heartbreaking', 'creator_words': 'hopeful but heartbreaking'}
        },
      },
      'prices': {'question': 2, 'outline': 25},
    };

Map<String, dynamic> _outlined({List<String> blocking = const []}) => {
      'id': 's1',
      'stage': 'outline',
      'outline_version': 1,
      'outline': {
        'title': 'The Dress',
        'premise': 'Amani finds a letter.',
        'characters': [
          {'name': 'Amani', 'role': 'protagonist', 'want': "clear her mother's name", 'flaw': 'trusts no one'}
        ],
        'secrets': [
          {'name': 'Who wrote the letter', 'revealed_in_chapter': 9}
        ],
        'chapters': [
          {
            'number': 1,
            'title': 'The Hem',
            'summary': 'She finds it.',
            'beats': ['a', 'b']
          }
        ],
        'ending': {'kind': 'bittersweet', 'description': 'She wins and loses.'},
        'assumptions': ['Set in Kigali today'],
      },
      'problems': blocking,
      'blocking': blocking,
      'prices': {'question': 2, 'outline': 25},
    };

Future<void> _pump(WidgetTester t, FakeNovelApi api) async {
  await t.pumpWidget(MaterialApp(
      home: Scaffold(
          body: SingleChildScrollView(
              child: StudioNovelCard(
                  projectId: 'p1', logline: 'A seamstress finds a letter in a wedding dress.', api: api)))));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('starts a novel from the idea and shows the first question', (t) async {
    final api = FakeNovelApi(null);
    await _pump(t, api);
    expect(find.text('Start my novel (free)'), findsOneWidget);
    await t.tap(find.text('Short · 12 chapters'));
    await t.pump();
    await t.tap(find.text('Start my novel (free)'));
    await t.pumpAndSettle();
    expect(api.calls.single, startsWith('start:short:0:A seamstress'));
    expect(find.text('What does she want most?'), findsOneWidget);
    expect(find.textContaining('How it should feel: hopeful but heartbreaking'), findsOneWidget);
    expect(find.textContaining('next question ~2 credits'), findsOneWidget);
  });

  testWidgets('answers, skips and finishes the interview', (t) async {
    final api = FakeNovelApi(_interviewing(question: {
      'topic': 'goal',
      'text': 'What does she want most?',
      'options': ['Justice']
    }));
    await _pump(t, api);
    await t.tap(find.text('Justice'));
    await t.pump();
    await t.tap(find.textContaining('Answer · next question'));
    await t.pumpAndSettle();
    expect(api.calls.last, 'interview:Justice:false:false');
    expect(find.textContaining('Plan the whole novel · up to 25 credits'), findsOneWidget);
  });

  testWidgets('shows the plan with VIYO\'s choices and approves it', (t) async {
    final api = FakeNovelApi(_outlined());
    await _pump(t, api);
    expect(find.text('The Dress'), findsOneWidget);
    expect(find.textContaining('VIYO chose these for you'), findsOneWidget);
    expect(find.textContaining('Set in Kigali today'), findsOneWidget);
    expect(find.textContaining('comes out in chapter 9'), findsOneWidget);
    await t.ensureVisible(find.text('Approve this plan'));
    await t.tap(find.text('Approve this plan'));
    await t.pumpAndSettle();
    expect(api.calls.last, 'approve:1');
    expect(find.textContaining('in the story memory'), findsOneWidget);
    expect(find.textContaining('Added: 6 characters, places and secrets; 20 facts; 2 threads.'), findsOneWidget);
  });

  testWidgets('a plan with blocking problems cannot be approved', (t) async {
    final api = FakeNovelApi(_outlined(blocking: ['The plan has 11 chapters; it needs exactly 12.']));
    await _pump(t, api);
    expect(find.textContaining('needs exactly 12'), findsOneWidget);
    final approve = t.widget<FilledButton>(
        find.ancestor(of: find.text('Approve this plan'), matching: find.byWidgetPredicate((w) => w is FilledButton)));
    expect(approve.onPressed, isNull);
  });
}
