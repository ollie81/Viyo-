import 'package:flutter_test/flutter_test.dart';
import 'package:viyo/models/ad_campaign.dart';

void main() {
  test('reads the universal product profile', () {
    final c = AdCampaign.fromJson({
      'id': 'c1',
      'user_id': 'u1',
      'promote_target': 'physical_product',
      'brand_name': 'Kivu Drinks',
      'product_subtype': 'drink',
      'facts': {'prices': ['RWF 800'], 'features': ['330 ml can']},
      'brand_colors': ['#E8452C'],
      'social_links': ['instagram.com/kivusunrise'],
      'contact': {'phone': '+250 788 123 456', 'email': null},
      'ad_style': 'product_cinematic',
      'character_mode': 'reuse',
      'character': {'name': 'Aline', 'saved_id': 'x'},
    });
    expect(c.productSubtype, 'drink');
    expect(c.facts['prices'], ['RWF 800']);
    expect(c.brandColors, ['#E8452C']);
    expect(c.contact, {'phone': '+250 788 123 456'});
    expect(c.characterMode, 'reuse');
    expect(c.character['name'], 'Aline');
  });

  test('old campaigns without a profile still load', () {
    final c = AdCampaign.fromJson({'id': 'c1', 'user_id': 'u1'});
    expect(c.facts, isEmpty);
    expect(c.adStyle, 'auto');
    expect(c.characterMode, 'auto');
  });
}
