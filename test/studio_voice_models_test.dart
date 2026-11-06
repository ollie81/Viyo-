import 'package:flutter_test/flutter_test.dart';
import 'package:viyo/services/creator_studio_service.dart';

void main() {
  test('a line keeps its delivery when read and saved again', () {
    final s = StudioScene.fromJson({
      'id': 's1',
      'position': 0,
      'dialogue': [
        {'character': 'Maya', 'text': 'Get out.', 'emotion': 'angry'},
        {'character': 'Maya', 'text': 'Please.'},
      ],
      'voice_outdated': ['Maya'],
    });
    expect(s.dialogue.map((l) => l.toJson()).toList(), [
      {'character': 'Maya', 'text': 'Get out.', 'emotion': 'angry'},
      {'character': 'Maya', 'text': 'Please.'},
    ]);
    expect(s.voiceOutdated, ['Maya']);
  });

  test('older scenes without the new fields still load', () {
    final s = StudioScene.fromJson({'id': 's1', 'dialogue': [{'character': 'A', 'text': 'Hi'}]});
    expect(s.voiceOutdated, isEmpty);
    expect(s.dialogue.single.emotion, '');
  });

  test('a character carries its voice details', () {
    final c = StudioCharacter.fromJson(
        {'id': 'c1', 'name': 'Maya', 'voice': 'Kore', 'voice_style': 'calm, low', 'voice_locked': true});
    expect(c.voice, 'Kore');
    expect(c.voiceStyle, 'calm, low');
    expect(c.voiceLocked, isTrue);
    final old = StudioCharacter.fromJson({'id': 'c2', 'name': 'Old', 'voice': 'Puck'});
    expect(old.voiceStyle, '');
    expect(old.voiceLocked, isFalse);
  });

  test('a delivery note from the scene list survives a save', () {
    final s = StudioScene.fromJson({
      'id': 's1',
      'dialogue': [
        {'character': 'Ana', 'text': 'Who is there?', 'emotion': 'frightened', 'delivery': 'whispered, shaky'},
      ],
    });
    expect(s.dialogue.single.toJson(),
        {'character': 'Ana', 'text': 'Who is there?', 'emotion': 'frightened', 'delivery': 'whispered, shaky'});
  });

  test('casting status and age come through for the character card', () {
    final kid = StudioCharacter.fromJson({
      'id': 'c1', 'name': 'Lily', 'voice': '', 'voice_status': 'needs_voice', 'age_label': 'young child', 'age_years': 7,
    });
    expect(kid.voiceStatus, 'needs_voice');
    expect(kid.ageLabel, 'young child');
    expect(kid.ageYears, 7);
    final old = StudioCharacter.fromJson({'id': 'c2', 'name': 'Old', 'voice': 'Puck'});
    expect(old.voiceStatus, 'cast');
    expect(StudioCharacter.fromJson({'id': 'c3', 'name': 'X', 'voice': ''}).voiceStatus, 'needs_voice');
  });

  test('the server asking to confirm a voice change is recognised', () {
    final e = StudioException('Maya already speaks in 2 recorded scenes.', 409)..code = 'confirm_voice_change';
    expect(e.needsVoiceChangeConfirm, isTrue);
    expect(e.needsReplaceConfirm, isFalse);
    expect((StudioException('x', 409)..code = 'confirm_replace').needsVoiceChangeConfirm, isFalse);
  });
}
