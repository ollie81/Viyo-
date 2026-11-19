import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viyo/models/post.dart';
import 'package:viyo/services/ads_studio_service.dart';
import 'package:viyo/widgets/ad_post_extras.dart';

Map<String, dynamic> _row(Map<String, dynamic> extra) =>
    {'id': 'p1', 'user_id': 'u1', 'post_type': 'video', 'created_at': '2026-11-19T10:00:00Z', ...extra};

void main() {
  test('ad posts are recognised; old posts read as normal posts', () {
    final ad = Post.fromJson(_row({'post_kind': 'ad', 'ad_link': 'https://kivusunrise.rw', 'ad_info': 'RWF 800'}));
    expect(ad.isAd, isTrue);
    expect(ad.adLink, 'https://kivusunrise.rw');
    expect(ad.copyWith(likeCount: 3).isAd, isTrue, reason: 'copyWith keeps the ad fields');
    expect(Post.fromJson(_row({})).isAd, isFalse);
  });

  test('visit links: websites, phone and email only', () {
    expect(AdVisitButton.uriFor('kivusunrise.rw')!.host, 'kivusunrise.rw');
    expect(AdVisitButton.labelFor('https://www.kivusunrise.rw'), 'Visit kivusunrise.rw');
    expect(AdVisitButton.labelFor('tel:+250788123456'), 'Call');
    expect(AdVisitButton.labelFor('mailto:hi@kivu.rw'), 'Email');
    expect(AdVisitButton.uriFor('javascript:alert(1)'), isNull);
    expect(AdVisitButton.uriFor(''), isNull);
  });

  test('publish options parse', () {
    final o = AdPublishOptions.fromJson({
      'can_publish': true,
      'categories': [
        {'key': 'food_drink', 'label': 'Food & drink'}
      ],
      'suggested': {'caption': 'Kivu', 'category': 'food_drink', 'link': '', 'product_info': 'RWF 800'},
      'thumbnails': [
        {'key': 'video', 'label': 'From the video', 'url': 'https://b/t.jpg'},
        {'key': 'cover', 'label': 'Ad cover', 'url': null},
      ],
      'published': {'post_id': 'p1', 'public': false, 'archived': false, 'caption': 'x', 'category': 'food_drink'},
    });
    expect(o.thumbnails.length, 1, reason: 'a choice without a link is skipped');
    expect(o.published!.public, isFalse);
    expect(o.suggested['product_info'], 'RWF 800');
  });

  testWidgets('the Ad label and Visit button render', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Column(children: [AdLabel(), AdVisitButton(link: 'kivusunrise.rw')])),
    ));
    expect(find.text('Ad'), findsOneWidget);
    expect(find.text('Visit kivusunrise.rw'), findsOneWidget);
  });
}
