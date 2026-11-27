import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viyo/screens/studio/studio_action_notes.dart';

void main() {
  testWidgets('an action shot shows its beat, movement and the flagged risk with a simpler alternative', (t) async {
    t.view.physicalSize = const Size(390, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: ShotActionNotes(action: {
          'beat': 'climax',
          'movement_direction': 'left_to_right',
          'environment_change': 'glass on the floor',
          'feasibility': [
            {'kind': 'vehicle', 'risk': 'high', 'issue': 'Vehicles crashing: shapes deform.',
             'alternative': 'Show the approach, cut on impact with sound, then the aftermath.'}
          ],
        }),
      ),
    ));
    expect(find.text('Climax · moving left to right · glass on the floor'), findsOneWidget);
    expect(find.textContaining('Simpler: Show the approach'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('a drama shot shows nothing extra', (t) async {
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: ShotActionNotes(action: null))));
    expect(find.byType(Text), findsNothing);
  });
}
