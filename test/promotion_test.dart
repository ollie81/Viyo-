import 'package:flutter_test/flutter_test.dart';
import 'package:viyo/models/post.dart';
import 'package:viyo/services/promotion_service.dart';

Post _p(Map<String, dynamic> extra) =>
    Post.fromJson({'id': 'p1', 'user_id': 'u', 'post_type': 'video', 'created_at': '2026-11-19T10:00:00Z', ...extra});

void main() {
  test('a promoted post is labelled as paid; a plain ad is not', () {
    final ad = _p({'post_kind': 'ad'});
    expect(ad.isPromoted, isFalse);
    final promoted = ad.copyWith(promotionId: 'pr1');
    expect(promoted.isPromoted && promoted.isAd, isTrue);
    expect(promoted.copyWith(likeCount: 2).promotionId, 'pr1', reason: 'copyWith keeps it');
    expect(_p({'is_boosted': true}).isPromoted, isTrue, reason: 'a coin boost is paid placement too');
  });

  test('quote and promotion parse', () {
    final q = PromotionQuote.fromJson({
      'budget_coins': 500, 'days': 5, 'coins_per_1000_impressions': 50, 'max_impressions': 10000,
      'per_day_coins': 100.0, 'terms': ['not guaranteed'], 'enabled': false,
    });
    expect(q.maxImpressions, 10000);
    expect(q.enabled, isFalse);
    final p = AdPromotion.fromJson({
      'id': 'x', 'post_id': 'p', 'status': 'ended', 'ended_reason': 'stopped', 'budget_coins': 500,
      'coins_spent': 12, 'impressions': 240, 'clicks': 9, 'coins_refunded': 488,
    });
    expect(p.active, isFalse);
    expect(p.coinsRefunded, 488);
  });
}
