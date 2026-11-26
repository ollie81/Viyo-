import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:viyo/models/post.dart';
import 'package:viyo/widgets/web_ad_card.dart';

Post ep({String owner = 'creator', int? number, bool? free, bool unlocked = false, String? series = 's1'}) =>
    Post.fromJson({
      'id': 'p${number ?? 0}', 'user_id': owner, 'created_at': '2026-11-26T10:00:00Z', 'post_type': 'video',
      if (series != null) 'series_id': series, if (number != null) 'episode_number': number,
      if (free != null) 'is_free': free,
    }).copyWith(unlockedByMe: unlocked);

void main() {
  test('free content carries ads; paid, unlocked and own content never does', () {
    expect(AdEligibility.forContent(ep(series: null), viewerId: 'v'), isTrue);              // a creator video
    expect(AdEligibility.forContent(ep(number: 1), viewerId: 'v'), isTrue);                  // free episode
    expect(AdEligibility.forContent(ep(number: 3), viewerId: null), isTrue);                 // guests too
    expect(AdEligibility.forContent(ep(number: 4), viewerId: 'v'), isFalse);                 // locked: not watched
    expect(AdEligibility.forContent(ep(number: 4, unlocked: true), viewerId: 'v'), isFalse); // paid for
    expect(AdEligibility.forContent(ep(number: 9, free: true), viewerId: 'v'), isTrue);      // creator made it free
    expect(AdEligibility.forContent(ep(number: 1, free: false, unlocked: true), viewerId: 'v'), isFalse);
    expect(AdEligibility.forContent(ep(series: null), viewerId: 'creator'), isFalse);        // own video
  });

  test('a series page has no ad for its creator or anyone who paid for an episode of it', () {
    final free = [ep(number: 1), ep(number: 2), ep(number: 4)];
    expect(AdEligibility.forSeries(seriesOwnerId: 'creator', episodes: free, viewerId: 'v'), isTrue);
    expect(AdEligibility.forSeries(seriesOwnerId: 'creator', episodes: free, viewerId: 'creator'), isFalse);
    final paid = [ep(number: 1, unlocked: true), ep(number: 4, unlocked: true)];
    expect(AdEligibility.forSeries(seriesOwnerId: 'creator', episodes: paid, viewerId: 'v'), isFalse);
  });

  test('payment, wallet, Premium, coins, donate, campaign and Studio credit screens never show ads', () {
    for (final f in AdEligibility.noAdScreenFiles) {
      final file = File('lib/screens/$f');
      expect(file.existsSync(), isTrue, reason: '$f is listed but missing');
      expect(file.readAsStringSync().contains('WebAdCard'), isFalse, reason: '$f must never show an ad');
    }
  });

  test('ads appear only in the reviewed places, once each', () {
    final uses = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart') || f.path.endsWith('web_ad_card.dart')) continue;
      final n = 'WebAdCard('.allMatches(f.readAsStringSync()).length;
      if (n > 0) uses.add('${f.path.replaceAll('\\', '/')}:$n');
    }
    uses.sort();
    expect(uses, [
      'lib/screens/dramas/drama_home_screen.dart:1',
      'lib/screens/feed_screen.dart:1',
      'lib/screens/post/series_detail_screen.dart:1',
      'lib/screens/post/video_player_screen.dart:1',
      'lib/screens/profile/profile_screen.dart:1',
      'lib/screens/search_screen.dart:1',
    ]);
  });
}
