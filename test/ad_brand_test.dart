import 'package:flutter_test/flutter_test.dart';
import 'package:viyo/models/ad_campaign.dart';
import 'package:viyo/services/ad_brands_service.dart';

void main() {
  test('a brand with its pictures, character and ads', () {
    final b = AdBrand.fromJson({
      'id': 'b1',
      'name': 'Kivu Sunrise',
      'promote_target': 'physical_product',
      'facts': {'prices': ['RWF 800']},
      'brand_colors': ['#E8452C'],
      'contact': {'phone': '+250 788 123 456', 'email': null},
      'character_id': 'c1',
      'logo_url': 'https://signed.test/logo.png',
      'assets': [
        {'id': 'a1', 'url': 'https://signed.test/p.png', 'asset_type': 'product_photo'}
      ],
      'characters': [
        {'id': 'c1', 'name': 'Aline', 'spec': {'appearance': 'curly hair'}, 'portrait_url': 'https://s/p.png'}
      ],
      'campaigns': [
        {'id': 'k1', 'status': 'ready', 'ad_style': 'lifestyle', 'published_post_id': 'p1'}
      ],
    });
    expect(b.facts['prices'], ['RWF 800']);
    expect(b.contact, {'phone': '+250 788 123 456'});
    expect(b.character!.name, 'Aline');
    expect(b.character!.appearance, 'curly hair');
    expect(b.assets.single.assetType, 'product_photo');
    expect(b.campaigns.single.published, isTrue);
  });

  test('a brand without a character', () {
    final b = AdBrand.fromJson({'id': 'b1', 'name': 'X'});
    expect(b.character, isNull);
    expect(b.archived, isFalse);
  });

  test('campaigns know their brand', () {
    expect(AdCampaign.fromJson({'id': 'c', 'user_id': 'u', 'brand_id': 'b1'}).brandId, 'b1');
    expect(AdCampaign.fromJson({'id': 'c', 'user_id': 'u'}).brandId, isNull);
  });
}
