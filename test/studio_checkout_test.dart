import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viyo/screens/studio/studio_checkout_screen.dart';
import 'package:viyo/screens/studio/studio_production_panel.dart';

Map<String, dynamic> quote({int total = 1100, int balance = 5000}) => {
      'stages': [
        {'stage': 'sheets', 'label': 'Character sheets', 'credits': 200, 'items': [{}, {}]},
        {'stage': 'images', 'label': 'Pictures', 'credits': 300, 'items': [{}, {}, {}]},
        {'stage': 'videos', 'label': 'Video clips', 'credits': 450, 'items': [{}, {}, {}]},
        {'stage': 'render', 'label': 'Final film', 'credits': 50, 'items': [{}]},
      ],
      'blocked': [],
      'advice': [],
      'steps_credits': 1000,
      'safety_credits': 100,
      'total_credits': total,
      'balance': {'available': balance},
      'estimate': {
        'categories': [
          {'key': 'story', 'label': 'Story development', 'remaining_max': 0, 'spent': 40, 'notes': ['Already written.']},
          {'key': 'characters', 'label': 'Characters (reference sheets)', 'remaining_max': 200, 'notes': []},
          {'key': 'storyboard', 'label': 'Scenes and storyboard', 'remaining_max': 300, 'notes': ['Varies.']},
          {'key': 'video', 'label': 'Video clips', 'remaining_max': 450, 'notes': []},
          {'key': 'voices', 'label': 'Voices', 'remaining_max': 0, 'notes': []},
          {'key': 'music', 'label': 'Music and sound effects', 'remaining_max': 0, 'notes': ['Included in the final film.']},
          {'key': 'render', 'label': 'Editing and final film', 'remaining_max': 50, 'notes': []},
        ],
        'steps_max': 1000,
        'safety_credits': 100,
        'max_credits': total,
        'episodes': {'in_this_production': 1, 'note': 'Later episodes are separate productions.'},
        'uncertainty': 'Prices can vary; you pay only what each step costs.',
      },
      'terms': {
        'credit_value_usd': 0.01,
        'credit_value_label': 'Estimated credit value: \$0.01 per credit. This is not cash value and not a guaranteed refund value.',
        'last_purchase': {'credits': 1500, 'price_usd': 16.32},
        'currencies': ['Studio credits pay for making films.', 'Premium doesn\'t include Studio credits.'],
        'budget': ['The production can never spend more than you approved.'],
        'failures': ['A step that fails is never charged.'],
        'revisions': ['Each shot gets one free fix for a confirmed defect.', 'Creative remakes are paid; you confirm the price.'],
        'publishing': ['One finished episode can be published on its own. There\'s no minimum number of episodes.',
          'You can download your films and post them anywhere.'],
        'storyboard': ['Before any video is made, the production stops for your storyboard review.'],
      },
    };

Future<Map<String, dynamic>?> openCheckout(WidgetTester t, Map<String, dynamic> q, {double width = 390}) async {
  t.view.physicalSize = Size(width, 5200);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  Map<String, dynamic>? result;
  await t.pumpWidget(MaterialApp(
    theme: ThemeData.dark(),
    home: Builder(
      builder: (ctx) => TextButton(
        onPressed: () async {
          result = await Navigator.of(ctx).push<Map<String, dynamic>>(MaterialPageRoute(
              builder: (_) => ProductionCheckoutScreen(
                  quote: q, requote: ({required bool sheets, required bool direct}) async => q)));
        },
        child: const Text('open'),
      ),
    ),
  ));
  await t.tap(find.text('open'));
  await t.pumpAndSettle();
  return result;
}

void main() {
  for (final width in [390.0, 1280.0]) {
    testWidgets('the checkout answers every question before paying (width $width)', (t) async {
      await openCheckout(t, quote(), width: width);
      // What am I buying? How many episodes?
      expect(find.text('What you\'re buying'), findsOneWidget);
      expect(find.text('Video clips (3)'), findsOneWidget);
      expect(find.textContaining('1 finished episode'), findsOneWidget);
      // The complete cost by part, and the most I can spend (with its value, clearly not cash).
      expect(find.text('Story development'), findsOneWidget);
      expect(find.text('spent 40 credits'), findsOneWidget);
      expect(find.text('up to 450 credits'), findsWidgets);
      expect(find.text('Maximum (reserved when you start)'), findsOneWidget);
      expect(find.text('1,100 credits'), findsWidgets);
      expect(find.text('≈ \$11.00'), findsOneWidget);
      expect(find.textContaining('not cash value'), findsOneWidget);
      expect(find.textContaining('\$16.32 (the price you actually paid)'), findsOneWidget);
      // Failures, revisions, publishing and export, and what credits are.
      expect(find.text('If something fails'), findsOneWidget);
      expect(find.text('Revisions included'), findsOneWidget);
      expect(find.textContaining('one free fix'), findsOneWidget);
      expect(find.text('Publishing and export'), findsOneWidget);
      expect(find.textContaining('no minimum number of episodes'), findsOneWidget);
      expect(find.text('Credits, Coins and Premium'), findsOneWidget);
      expect(find.textContaining('never spend more than you approved'), findsOneWidget);
      expect(find.text('Reserve up to 1,100 credits & start'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('storyboard review is on by default and turning it off is a deliberate choice', (t) async {
    await openCheckout(t, quote());
    final sw = find.widgetWithText(SwitchListTile, 'Review the storyboard before video');
    expect(t.widget<SwitchListTile>(sw).value, isTrue);
    await t.tap(sw);
    await t.pumpAndSettle();
    expect(find.text('Skip the storyboard review?'), findsOneWidget);
    await t.tap(find.text('Keep the review'));
    await t.pumpAndSettle();
    expect(t.widget<SwitchListTile>(sw).value, isTrue, reason: 'still on unless deliberately skipped');
    await t.tap(sw);
    await t.pumpAndSettle();
    await t.tap(find.text('Skip it'));
    await t.pumpAndSettle();
    expect(t.widget<SwitchListTile>(sw).value, isFalse);
  });

  testWidgets('starting returns the approved maximum and the storyboard choice', (t) async {
    Map<String, dynamic>? got;
    t.view.physicalSize = const Size(390, 5200);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => TextButton(
          onPressed: () async => got = await Navigator.of(ctx).push<Map<String, dynamic>>(MaterialPageRoute(
              builder: (_) => ProductionCheckoutScreen(
                  quote: quote(), requote: ({required bool sheets, required bool direct}) async => quote()))),
          child: const Text('open'),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    await t.tap(find.text('Reserve up to 1,100 credits & start'));
    await t.pumpAndSettle();
    expect(got, {'total': 1100, 'sheets': true, 'direct': true, 'storyboard': true});
  });

  testWidgets('not enough credits: asks for credits instead of starting', (t) async {
    await openCheckout(t, quote(balance: 300));
    expect(find.textContaining('You need 800 credits more'), findsOneWidget);
    expect(find.text('Get credits'), findsOneWidget);
    expect(find.text('Reserve up to 1,100 credits & start'), findsNothing);
  });

  Future<void> tracker(WidgetTester t, Map<String, dynamic> run, {VoidCallback? onApproveBudget, VoidCallback? onApproveStoryboard}) async {
    t.view.physicalSize = const Size(390, 2000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView(children: ProductionTracker.build(
          run: run,
          working: false,
          onResume: () {},
          onApproveBudget: onApproveBudget ?? () {},
          onApproveStoryboard: onApproveStoryboard ?? () {},
          onHistory: () {},
          onStop: () {},
        )),
      ),
    ));
  }

  Map<String, dynamic> run(String status, {Map<String, dynamic> extra = const {}}) => {
        'id': 'r1', 'status': status, 'percent': 40, 'approved_credits': 1100, 'spent_credits': 300,
        'refunded_credits': 25, 'reserved_left': 600, 'remaining_budget': 700, 'next_step': 'Video clips',
        'stages': [
          {'label': 'Pictures', 'total': 3, 'done': 3, 'working': 0, 'failed': 1},
          {'label': 'Video clips', 'total': 3, 'done': 0, 'working': 0, 'failed': 0},
        ],
        ...extra,
      };

  testWidgets('the tracker shows where the money is and what comes next', (t) async {
    await tracker(t, run('running'));
    expect(find.text('Approved budget'), findsOneWidget);
    expect(find.text('Spent so far'), findsOneWidget);
    expect(find.text('25 credits'), findsOneWidget);
    expect(find.text('Left in your approved budget'), findsOneWidget);
    expect(find.text('700 credits'), findsOneWidget);
    expect(find.text('Video clips'), findsWidgets);
    expect(find.text('1 retried (not charged)'), findsOneWidget);
  });

  testWidgets('more credits: shows why, the extra and the new maximum, and waits for approval', (t) async {
    var asked = false;
    await tracker(t, run('needs_approval', extra: {'needs_credits': 150, 'problem': 'The director planned more shots.'}),
        onApproveBudget: () => asked = true);
    expect(find.text('Waiting for your approval (budget)'), findsOneWidget);
    expect(find.textContaining('The director planned more shots.'), findsOneWidget);
    expect(find.textContaining('Extra: 150 credits · new maximum 1,250 credits'), findsOneWidget);
    expect(find.textContaining('Nothing continues until you approve'), findsOneWidget);
    await t.tap(find.text('Review & approve credits'));
    expect(asked, isTrue);
  });

  testWidgets('the storyboard review waits for the creator', (t) async {
    var approved = false;
    await tracker(t, run('storyboard_review', extra: {'problem': 'Your storyboard is ready.'}),
        onApproveStoryboard: () => approved = true);
    expect(find.text('Waiting for your storyboard review'), findsOneWidget);
    await t.tap(find.text('Approve storyboard'));
    expect(approved, isTrue);
  });

  testWidgets('the credit history lists every charge, refund and return', (t) async {
    await t.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: ProductionHistorySheet(history: {
          'totals': {'approved': 1100, 'charged': 300, 'refunded': 25, 'returned': 775},
          'events': [
            {'kind': 'reserved', 'credits': 1100, 'note': 'Approved budget reserved.'},
            {'kind': 'returned', 'credits': 775, 'note': 'Unused reservation returned.'},
          ],
          'steps': [
            {'label': 'Scene 1 picture', 'status': 'failed', 'try': 1, 'held': 25, 'charged': 0, 'refunded': 25},
            {'label': 'Scene 1 picture', 'status': 'succeeded', 'try': 2, 'held': 25, 'charged': 20, 'refunded': 5},
          ],
        }),
      ),
    ));
    expect(find.text('Charged: 300 credits'), findsOneWidget);
    expect(find.text('Returned: 775 credits'), findsOneWidget);
    expect(find.text('Failed: not charged, 25 credits refunded'), findsOneWidget);
    expect(find.text('Scene 1 picture (try 2)'), findsOneWidget);
    expect(find.text('Charged 20 credits · 5 credits refunded'), findsOneWidget);
  });
}
