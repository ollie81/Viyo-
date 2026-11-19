import 'package:flutter_test/flutter_test.dart';
import 'package:viyo/services/ad_insights_service.dart';

void main() {
  test('insights keep organic and paid apart and unknown days stay unknown', () {
    final d = AdInsights.fromJson({
      'days': 7,
      'totals': {
        'organic': {'ads': 2, 'views': 1000, 'likes': 40, 'comments': 6, 'shares': 4, 'engagement_rate': 0.05},
        'paid': {'ads': 1, 'views': 900, 'likes': 9, 'comments': 0, 'shares': 0, 'engagement_rate': 0.01},
      },
      'posts': [
        {'post_id': 'p1', 'caption': 'Kivu', 'views': 1000, 'likes': 40, 'comments': 6, 'shares': 4, 'engagement_rate': 0.05, 'paid': false}
      ],
      'trend': [
        {'day': '2026-11-18', 'likes': 2, 'comments': 0, 'views': null, 'shares': null},
        {'day': '2026-11-19', 'likes': 0, 'comments': 1, 'views': 200, 'shares': 3},
      ],
      'followers': {'total': 12, 'gained': 3},
      'notes': ['x'],
    });
    expect(d.organic.views, 1000);
    expect(d.paid.views, 900);
    expect(d.paidAds, 1);
    expect(d.trend.first.views, isNull);
    expect(d.trend.last.views, 200);
    expect(d.followersGained, 3);
    expect(d.posts.single.stats.engagementRate, 0.05);
  });

  test('experiment with a leader, and one without enough data', () {
    final e = AdExperiment.fromJson({
      'id': 'e1',
      'name': 'Kivu: Funny vs Emotional',
      'variants': [
        {'campaign_id': 'c1', 'tone': 'funny', 'label': 'Funny', 'status': 'ready', 'published': true, 'public': true,
         'stats': {'views': 2000, 'likes': 200, 'comments': 0, 'shares': 0}},
        {'campaign_id': 'c2', 'tone': 'emotional', 'label': 'Emotional', 'status': 'draft', 'published': false},
      ],
      'comparison': {'verdict': 'leader', 'leader': 'Funny', 'message': 'Funny is more engaging so far'},
    });
    expect(e.leader, 'Funny');
    expect(e.variants.last.stats, isNull);
    expect(AdExperiment.fromJson({'id': 'e', 'variants': [], 'comparison': {}}).verdict, 'not_enough_data');
  });
}
