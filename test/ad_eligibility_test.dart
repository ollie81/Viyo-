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
      'lib/screens/post/series_detail_screen.dart:2', // display below episodes + multiplex below similar dramas
      'lib/screens/post/video_player_screen.dart:3', // below the player OR the desktop side rail, + multiplex
      'lib/screens/profile/profile_screen.dart:1',
      'lib/screens/search_screen.dart:2', // discover feed + between movie / drama cards
    ]);
  });

  test('ad sizes adapt: phone, tablet, desktop', () {
    double h(WebAdKind k, double w, [WebAdSize s = WebAdSize.inline]) => WebAdLayout.height(k, s, w);
    expect([h(WebAdKind.display, 390), h(WebAdKind.display, 800), h(WebAdKind.display, 1440)], [280, 250, 200]);
    expect([h(WebAdKind.infeed, 390), h(WebAdKind.infeed, 1280)], [300, 260]);
    expect([h(WebAdKind.multiplex, 390), h(WebAdKind.multiplex, 800), h(WebAdKind.multiplex, 1440)], [520, 420, 380]);
    expect(h(WebAdKind.display, 1440, WebAdSize.rail), 600);
    expect(WebAdLayout.railMinScreen, 1100);          // laptops 1100+ and desktops get the side rail
  });

  test('the in-feed and multiplex units are used only once set up', () {
    final c = WebAdsConfig.fromJson({'enabled': true, 'client': 'ca-pub-4161816109605295', 'slot': '6118261645'});
    expect(c.infeedSlot, isNull);
    expect(c.multiplexSlot, isNull);
    final d = WebAdsConfig.fromJson({'enabled': true, 'client': 'ca-pub-1234567890', 'slot': '6118261645',
        'infeed_slot': '111111', 'infeed_layout_key': '-fb+5w', 'multiplex_slot': '222222'});
    expect([d.infeedSlot, d.infeedLayoutKey, d.multiplexSlot], ['111111', '-fb+5w', '222222']);
  });

  test('each placement uses the agreed AdSense unit', () {
    String src(String f) => File('lib/screens/$f').readAsStringSync().replaceAll(RegExp(r'\s+'), ' ');
    // Display: home feed, drama/movie detail, creator profiles (and the long-video page).
    expect(src('feed_screen.dart'), isNot(contains('kind: WebAdKind.infeed')));
    expect(src('post/series_detail_screen.dart'), contains("WebAdCard(placement: 'series', margin"));
    expect(src('profile/profile_screen.dart'), contains("WebAdCard(placement: 'profile', margin"));
    // In-feed: between drama cards, between movie cards, discovery feeds.
    expect(src('dramas/drama_home_screen.dart'), contains("WebAdCard(placement: 'dramas', kind: WebAdKind.infeed)"));
    expect(src('search_screen.dart'), contains("placement: 'discover-\${_cat.name}', kind: WebAdKind.infeed"));
    expect(src('search_screen.dart'), contains("WebAdCard(placement: 'discover', kind: WebAdKind.infeed"));
    // Multiplex: below drama/movie recommendations and on the long-video page.
    expect(src('post/series_detail_screen.dart'), contains("placement: 'series-multiplex', kind: WebAdKind.multiplex"));
    expect(src('post/video_player_screen.dart'), contains("placement: 'player-multiplex', kind: WebAdKind.multiplex"));
  });

  test('the in-feed unit uses its fluid format and layout key from the server config', () {
    final c = WebAdsConfig.fromJson({'enabled': true, 'client': 'ca-pub-4161816109605295', 'slot': '6118261645',
        'infeed_slot': '3636015645', 'infeed_layout_key': '-fb+5w+4e-db+86', 'multiplex_slot': '2527655942'});
    expect([c.slot, c.infeedSlot, c.infeedLayoutKey, c.multiplexSlot],
        ['6118261645', '3636015645', '-fb+5w+4e-db+86', '2527655942']);
    final web = File('lib/services/adsense_web.dart').readAsStringSync();
    expect(web, contains("setAttribute('data-ad-layout-key', layoutKey)"));
    expect(File('lib/widgets/web_ad_card.dart').readAsStringSync(), contains("(cfg.infeedSlot!, 'fluid', cfg.infeedLayoutKey)"));
    expect(web.contains('enable_page_level_ads') || web.contains('data-ad-client=') && web.contains('<script'), isFalse,
        reason: 'no Auto ads code');
  });
}
