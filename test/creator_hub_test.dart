import 'package:flutter_test/flutter_test.dart';
import 'package:viyo/models/series.dart';
import 'package:viyo/services/creator_hub_service.dart';

void main() {
  test('Creator Hub reads real totals, productions and the earning rules', () {
    final h = CreatorHub.fromJson({
      'audience': {'views': 6700, 'likes': 90, 'comments': 5, 'shares': 2, 'followers': 1},
      'earnings': {
        'lifetime_coins': 300, 'lifetime_usd': 1.8, 'available_coins': 200, 'available_usd': 1.2,
        'pending_coins': 0, 'paid_coins': 100, 'paid_usd': 0.6, 'last_30_days_coins': 200,
        'can_withdraw': false, 'payout_details_saved': false, 'withdrawal_pending': false,
      },
      'productions': [
        {'kind': 'series', 'id': 's1', 'title': 'Kigali Nights', 'content_type': 'short_drama', 'episodes': 2,
         'public_episodes': 1, 'coin_price': 30, 'earns': true, 'views': 1400, 'likes': 60, 'comments': 5,
         'shares': 2, 'earned_coins': 300},
      ],
      'how_you_earn': {
        'earns': [{'title': 'Paid episodes and movies', 'detail': 'you get 65%'}],
        'does_not_earn': ['free coins'],
        'payout': {'detail': 'From \$10'},
        'note': 'VIYO pays only from coins viewers actually bought',
      },
    });
    expect(h.views, 6700);
    expect(h.followers, 1);
    expect(h.availableUsd, 1.2);
    expect(h.productions.single.earnedCoins, 300);
    expect(h.earns.single.detail, contains('65%'));
    expect(h.doesNotEarn, ['free coins']);
  });

  test('a new creator with nothing yet', () {
    final h = CreatorHub.fromJson({});
    expect(h.productions, isEmpty);
    expect(h.lifetimeCoins, 0);
  });

  test('editing a series keeps or changes its price', () {
    final s = Series.fromJson({'id': 's', 'user_id': 'u', 'title': 'T', 'created_at': '2026-11-19T10:00:00Z',
        'coin_price_per_episode': 30});
    expect(s.copyWith(title: 'New').coinPricePerEpisode, 30);
    expect(s.copyWith(coinPricePerEpisode: 45).coinPricePerEpisode, 45);
  });
}
