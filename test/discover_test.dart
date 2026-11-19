import 'package:flutter_test/flutter_test.dart';
import 'package:viyo/models/post.dart';
import 'package:viyo/services/discover_service.dart';

Post _p(String id, {bool ad = false}) => Post.fromJson({
      'id': id,
      'user_id': 'u',
      'post_type': 'video',
      'created_at': '2026-11-19T10:00:00Z',
      'post_kind': ad ? 'ad' : 'post',
    });

void main() {
  test('the six categories, in order', () {
    expect(DiscoverCategory.values.map((c) => c.label).toList(),
        ['For You', 'Shorts', 'Movies', 'Dramas', 'Ads', 'Photos']);
    expect(DiscoverCategory.movies.isSeries && DiscoverCategory.dramas.isSeries, isTrue);
    expect(DiscoverCategory.ads.isSeries, isFalse);
  });

  test('For You keeps ads spaced out and never first', () {
    final ranked = [
      _p('a1', ad: true), _p('a2', ad: true), _p('a3', ad: true),
      for (var i = 0; i < 14; i++) _p('p$i'),
    ];
    final out = DiscoverService.capAds(ranked);
    final adAt = [for (var i = 0; i < out.length; i++) if (out[i].isAd) i];
    expect(adAt.first, 3, reason: 'not in the first three tiles');
    for (var i = 1; i < adAt.length; i++) {
      expect(adAt[i] - adAt[i - 1], greaterThanOrEqualTo(6));
    }
    expect(out.where((p) => !p.isAd).map((p) => p.id).toList(), [for (var i = 0; i < 14; i++) 'p$i'],
        reason: 'ordinary posts keep their order and none are lost');
  });

  test('no ads: unchanged; only ads: none in For You (they are in the Ads category)', () {
    final plain = [for (var i = 0; i < 5; i++) _p('p$i')];
    expect(DiscoverService.capAds(plain).map((p) => p.id), plain.map((p) => p.id));
    expect(DiscoverService.capAds([_p('a', ad: true)]), isEmpty);
  });

  test('ad categories match the backend list', () {
    expect(kAdCategories.keys, contains('food_drink'));
    expect(kAdCategories.length, 11);
  });
}
