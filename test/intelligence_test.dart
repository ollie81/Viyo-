import 'package:flutter_test/flutter_test.dart';
import 'package:viyo/services/creator_hub_service.dart';

void main() {
  test('creator analytics read real, de-duplicated numbers and evidence-backed advice', () {
    final a = CreatorAnalytics.fromJson({
      'totals': {'unique_viewers': 30, 'completers': 24, 'engaged_viewers': 5, 'watch_minutes': 60.0,
                 'followers': 2, 'new_followers': 1, 'earned_coins': 20},
      'productions': [
        {'kind': 'series', 'id': 's1', 'title': 'Kigali Nights', 'unique_viewers': 30}
      ],
      'advice': [
        {'text': 'Most viewers of "Kigali Nights" stop after episode 1', 'based_on': '30 episode-1 viewers'}
      ],
      'note': 'each person once',
    });
    expect(a.uniqueViewers, 30);
    expect(a.watchMinutes, 60.0);
    expect(a.advice.single.basedOn, '30 episode-1 viewers');
    expect(a.productions.single['title'], 'Kigali Nights');
  });

  test('empty analytics for a new creator', () {
    final a = CreatorAnalytics.fromJson({});
    expect(a.uniqueViewers, 0);
    expect(a.advice, isEmpty);
  });
}
