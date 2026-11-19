import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../constants/supabase_constants.dart';
import '../models/ad_campaign.dart';

/// A brand saved in My Brands. Pictures come back as short-lived signed links (they're private files).
class AdBrand {
  final String id;
  final String name;
  final String description;
  final String promoteTarget;
  final String productSubtype;
  final String website;
  final String ctaText;
  final String targetAudience;
  final Map<String, List<String>> facts;
  final List<String> brandColors;
  final List<String> socialLinks;
  final Map<String, String> contact;
  final bool archived;
  final String? characterId;
  final String? logoUrl;
  final List<AdBrandAsset> assets;
  final List<AdBrandCharacter> characters;
  final List<AdBrandCampaign> campaigns;

  AdBrand({
    required this.id,
    required this.name,
    this.description = '',
    this.promoteTarget = 'physical_product',
    this.productSubtype = '',
    this.website = '',
    this.ctaText = '',
    this.targetAudience = '',
    this.facts = const {},
    this.brandColors = const [],
    this.socialLinks = const [],
    this.contact = const {},
    this.archived = false,
    this.characterId,
    this.logoUrl,
    this.assets = const [],
    this.characters = const [],
    this.campaigns = const [],
  });

  AdBrandCharacter? get character => characters.where((c) => c.id == characterId).firstOrNull;

  factory AdBrand.fromJson(Map<String, dynamic> j) => AdBrand(
        id: j['id'] as String,
        name: (j['name'] ?? '').toString(),
        description: (j['description'] ?? '').toString(),
        promoteTarget: (j['promote_target'] ?? 'physical_product').toString(),
        productSubtype: (j['product_subtype'] ?? '').toString(),
        website: (j['website'] ?? '').toString(),
        ctaText: (j['cta_text'] ?? '').toString(),
        targetAudience: (j['target_audience'] ?? '').toString(),
        facts: {
          if (j['facts'] is Map)
            for (final e in (j['facts'] as Map).entries)
              e.key.toString(): ((e.value as List?) ?? []).map((v) => v.toString()).toList(),
        },
        brandColors: ((j['brand_colors'] as List?) ?? []).map((e) => e.toString()).toList(),
        socialLinks: ((j['social_links'] as List?) ?? []).map((e) => e.toString()).toList(),
        contact: {
          if (j['contact'] is Map)
            for (final e in (j['contact'] as Map).entries)
              if (e.value != null) e.key.toString(): e.value.toString(),
        },
        archived: j['archived'] == true,
        characterId: j['character_id'] as String?,
        logoUrl: j['logo_url'] as String?,
        assets: [for (final a in (j['assets'] as List? ?? const [])) AdBrandAsset.fromJson(Map<String, dynamic>.from(a as Map))],
        characters: [
          for (final c in (j['characters'] as List? ?? const [])) AdBrandCharacter.fromJson(Map<String, dynamic>.from(c as Map))
        ],
        campaigns: [
          for (final c in (j['campaigns'] as List? ?? const [])) AdBrandCampaign.fromJson(Map<String, dynamic>.from(c as Map))
        ],
      );
}

class AdBrandAsset {
  final String id;
  final String url;
  final String assetType;
  final String label;
  AdBrandAsset({required this.id, required this.url, required this.assetType, this.label = ''});
  factory AdBrandAsset.fromJson(Map<String, dynamic> j) => AdBrandAsset(
      id: j['id'] as String, url: (j['url'] ?? '').toString(), assetType: (j['asset_type'] ?? 'other').toString(),
      label: (j['label'] ?? '').toString());
}

class AdBrandCharacter {
  final String id;
  final String name;
  final String appearance;
  final String? portraitUrl;
  AdBrandCharacter({required this.id, required this.name, this.appearance = '', this.portraitUrl});
  factory AdBrandCharacter.fromJson(Map<String, dynamic> j) => AdBrandCharacter(
      id: j['id'] as String,
      name: (j['name'] ?? '').toString(),
      appearance: ((j['spec'] as Map?)?['appearance'] ?? '').toString(),
      portraitUrl: j['portrait_url'] as String?);
}

class AdBrandCampaign {
  final String id;
  final String status;
  final String adStyle;
  final String? thumbnailUrl;
  final bool published;
  final DateTime? createdAt;
  AdBrandCampaign({required this.id, required this.status, required this.adStyle, this.thumbnailUrl,
      this.published = false, this.createdAt});
  factory AdBrandCampaign.fromJson(Map<String, dynamic> j) => AdBrandCampaign(
      id: j['id'] as String,
      status: (j['status'] ?? 'draft').toString(),
      adStyle: (j['ad_style'] ?? 'auto').toString(),
      thumbnailUrl: j['thumbnail_url'] as String?,
      published: j['published_post_id'] != null,
      createdAt: DateTime.tryParse((j['created_at'] ?? '').toString()));
}

/// My Brands (creator Ads Maker only): the creator's own brands, with their own sign-in.
class AdBrandsService {
  static const _base = '${AiBackendConstants.baseUrl}/api/v1/ads-maker/brands';

  static Map<String, String> _headers({bool json = true}) {
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    return {if (json) 'Content-Type': 'application/json', if (token != null) 'Authorization': 'Bearer $token'};
  }

  static Exception _failure(http.Response res, String action) {
    try {
      final d = jsonDecode(res.body)['detail'];
      if (d is String) return Exception(d);
    } catch (_) {}
    return Exception('Could not $action (${res.statusCode})');
  }

  static Future<List<AdBrand>> list({bool includeArchived = false}) async {
    final res = await http.get(Uri.parse('$_base${includeArchived ? '?include_archived=true' : ''}'), headers: _headers());
    if (res.statusCode != 200) throw _failure(res, 'load your brands');
    return (jsonDecode(res.body) as List).map((e) => AdBrand.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<AdBrand> get(String id) async {
    final res = await http.get(Uri.parse('$_base/$id'), headers: _headers());
    if (res.statusCode != 200) throw _failure(res, 'load the brand');
    return AdBrand.fromJson(jsonDecode(res.body));
  }

  static Future<AdBrand> create(Map<String, dynamic> fields) async {
    final res = await http.post(Uri.parse(_base), headers: _headers(), body: jsonEncode(fields));
    if (res.statusCode != 200) throw _failure(res, 'save the brand');
    return AdBrand.fromJson(jsonDecode(res.body));
  }

  static Future<AdBrand> update(String id, Map<String, dynamic> fields) async {
    final res = await http.put(Uri.parse('$_base/$id'), headers: _headers(), body: jsonEncode(fields));
    if (res.statusCode != 200) throw _failure(res, 'save the brand');
    return AdBrand.fromJson(jsonDecode(res.body));
  }

  static Future<AdBrandAsset> uploadAsset(String id, Uint8List bytes, String filename, String assetType) async {
    final req = http.MultipartRequest('POST', Uri.parse('$_base/$id/assets?asset_type=$assetType'))
      ..headers.addAll(_headers(json: false));
    final ext = filename.contains('.') ? filename.split('.').last.toLowerCase() : 'jpg';
    final type = ext == 'png' ? MediaType('image', 'png') : (ext == 'webp' ? MediaType('image', 'webp') : MediaType('image', 'jpeg'));
    req.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename, contentType: type));
    final res = await http.Response.fromStream(await req.send());
    if (res.statusCode != 200) throw _failure(res, 'upload the picture');
    return AdBrandAsset.fromJson(jsonDecode(res.body));
  }

  static Future<void> deleteAsset(String id, String assetId) async {
    final res = await http.delete(Uri.parse('$_base/$id/assets/$assetId'), headers: _headers());
    if (res.statusCode != 200) throw _failure(res, 'remove the picture');
  }

  static Future<AdBrand> setCharacter(String id, String characterId) async {
    final res = await http.put(Uri.parse('$_base/$id/character/$characterId'), headers: _headers());
    if (res.statusCode != 200) throw _failure(res, 'set the character');
    return AdBrand.fromJson(jsonDecode(res.body));
  }

  static Future<AdBrand> clearCharacter(String id) async {
    final res = await http.delete(Uri.parse('$_base/$id/character'), headers: _headers());
    if (res.statusCode != 200) throw _failure(res, 'change the character');
    return AdBrand.fromJson(jsonDecode(res.body));
  }

  /// Saves an ad's details, pictures and character as a brand (or returns its brand if it has one).
  static Future<AdBrand> saveCampaignAsBrand(String campaignId) async {
    final res = await http.post(Uri.parse('$_base/from-campaign/$campaignId'), headers: _headers());
    if (res.statusCode != 200) throw _failure(res, 'save as a brand');
    return AdBrand.fromJson(jsonDecode(res.body));
  }

  /// A new ad campaign filled in from the brand (its details, its own copy of the pictures, its character).
  static Future<AdCampaign> newAd(String id,
      {String adStyle = 'auto', String aspectRatio = '9:16', int durationSeconds = 15, bool useCharacter = true}) async {
    final res = await http.post(Uri.parse('$_base/$id/campaigns'),
        headers: _headers(),
        body: jsonEncode({
          'ad_style': adStyle,
          'aspect_ratio': aspectRatio,
          'duration_seconds': durationSeconds,
          'use_character': useCharacter,
        }));
    if (res.statusCode != 200) throw _failure(res, 'start the ad');
    return AdCampaign.fromJson(jsonDecode(res.body));
  }
}
