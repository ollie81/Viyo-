import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../constants/supabase_constants.dart';
import '../models/ad_asset.dart';
import '../models/ad_campaign.dart';
import '../models/ad_hook.dart';
import '../models/ad_job.dart';

/// Server-computed hooks + which format Gemini recommended for this
/// campaign — see ads_studio.py's HOOK_SCORE_WEIGHTS for how scoreTotal
/// is actually computed (a transparent weighted sum, not trusted
/// straight from the model).
class AdHookGenerationResult {
  final List<AdHook> hooks;
  final String recommendedFormat;
  final int costUsdCents;
  AdHookGenerationResult({required this.hooks, required this.recommendedFormat, required this.costUsdCents});
}

class AdScriptResult {
  final List<Map<String, dynamic>> scenes;
  final int costUsdCents;
  AdScriptResult({required this.scenes, required this.costUsdCents});
}

class PromoteViyoDefaults {
  final String targetName;
  final String targetDescription;
  final List<String> targetFeatures;
  final String ctaText;
  PromoteViyoDefaults({
    required this.targetName,
    required this.targetDescription,
    required this.targetFeatures,
    required this.ctaText,
  });
}

class AdFormatInfo {
  final String key;
  final String label;
  AdFormatInfo({required this.key, required this.label});
}

class VeoTierInfo {
  final String key;
  final String label;
  final int pricePerSecCents;
  VeoTierInfo({required this.key, required this.label, required this.pricePerSecCents});
}

/// Talks to viyo_ai's ads_studio.py — same X-Admin-Key gate every other
/// admin surface in this app uses (see StudioService), and the exact
/// same request/response/error-handling shape as that file so the two
/// services stay easy to maintain side by side.
class AdsStudioService {
  static const _base = '${AiBackendConstants.baseUrl}/api/v1/admin/ads-studio';

  static Map<String, String> _headers(String adminKey) => {
        'Content-Type': 'application/json',
        'X-Admin-Key': adminKey,
      };

  static String? _errorDetail(http.Response res) {
    try {
      final data = jsonDecode(res.body);
      final detail = data is Map ? data['detail'] : null;
      return detail is String ? detail : null;
    } catch (_) {
      return null;
    }
  }

  static Exception _failure(http.Response res, String action) =>
      Exception(_errorDetail(res) ?? 'Could not $action (${res.statusCode})');

  // http.MultipartFile.fromBytes has no way to infer a Content-Type from
  // the bytes/filename the way fromPath does (that inference is backed by
  // the `mime` package, only wired into fromPath) — it defaults silently
  // to application/octet-stream whenever contentType: isn't passed
  // explicitly. Every asset upload was sending that default, which the
  // backend's own (correct) "Only image files are supported here." check
  // then rejected every single time — confirmed live via screen
  // recording: the picker and the upload both ran fine, the backend 400'd
  // on content-type. Both upload methods below now explicitly declare a
  // real image Content-Type inferred from the picked file's own extension
  // (this screen only ever offers FileType.image, so the fallback for an
  // unrecognized/missing extension is still a safe, always-correct choice).
  static MediaType _imageMediaType(String filename) {
    final ext = filename.contains('.') ? filename.split('.').last.toLowerCase() : '';
    switch (ext) {
      case 'png':
        return MediaType('image', 'png');
      case 'gif':
        return MediaType('image', 'gif');
      case 'webp':
        return MediaType('image', 'webp');
      case 'heic':
        return MediaType('image', 'heic');
      case 'heif':
        return MediaType('image', 'heif');
      case 'bmp':
        return MediaType('image', 'bmp');
      default:
        return MediaType('image', 'jpeg');
    }
  }

  // --- Campaigns ---------------------------------------------------------

  static Future<AdCampaign> createCampaign(
    String adminKey, {
    required String userId,
    required String promoteTarget,
    String targetName = '',
    String targetDescription = '',
    List<String> targetFeatures = const [],
    String targetAudience = '',
    String objective = '',
    String destinationLink = '',
    String ctaText = '',
    String? format,
    int durationSeconds = 15,
    String aspectRatio = '9:16',
    String resolution = '720p',
    bool useVeo = false,
    String veoTier = 'lite',
    String? voiceGenderPreference,
  }) async {
    final res = await http.post(
      Uri.parse('$_base/campaign'),
      headers: _headers(adminKey),
      body: jsonEncode({
        'user_id': userId,
        'promote_target': promoteTarget,
        'target_name': targetName,
        'target_description': targetDescription,
        'target_features': targetFeatures,
        'target_audience': targetAudience,
        'objective': objective,
        'destination_link': destinationLink,
        'cta_text': ctaText,
        if (format != null) 'format': format,
        'duration_seconds': durationSeconds,
        'aspect_ratio': aspectRatio,
        'resolution': resolution,
        'use_veo': useVeo,
        'veo_tier': veoTier,
        if (voiceGenderPreference != null) 'voice_gender_preference': voiceGenderPreference,
      }),
    );
    if (res.statusCode != 200) throw _failure(res, 'create campaign');
    return AdCampaign.fromJson(jsonDecode(res.body));
  }

  static Future<List<VeoTierInfo>> listVeoTiers(String adminKey) async {
    final res = await http.get(Uri.parse('$_base/veo-tiers'), headers: _headers(adminKey));
    if (res.statusCode != 200) throw _failure(res, 'load Veo tiers');
    return (jsonDecode(res.body) as List)
        .map((e) => VeoTierInfo(key: e['key'] as String, label: e['label'] as String, pricePerSecCents: (e['price_per_sec_cents'] as num).toInt()))
        .toList();
  }

  static Future<AdCampaign> updateCampaign(String adminKey, String campaignId, Map<String, dynamic> patch) async {
    final res = await http.put(
      Uri.parse('$_base/campaign/$campaignId'),
      headers: _headers(adminKey),
      body: jsonEncode(patch),
    );
    if (res.statusCode != 200) throw _failure(res, 'update campaign');
    return AdCampaign.fromJson(jsonDecode(res.body));
  }

  static Future<List<AdCampaign>> listCampaigns(String adminKey) async {
    final res = await http.get(Uri.parse('$_base/campaigns'), headers: _headers(adminKey));
    if (res.statusCode != 200) throw _failure(res, 'load campaigns');
    return (jsonDecode(res.body) as List).map((e) => AdCampaign.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<AdCampaign> getCampaign(String adminKey, String campaignId) async {
    final res = await http.get(Uri.parse('$_base/campaign/$campaignId'), headers: _headers(adminKey));
    if (res.statusCode != 200) throw _failure(res, 'load campaign');
    return AdCampaign.fromJson(jsonDecode(res.body));
  }

  static Future<void> deleteCampaign(String adminKey, String campaignId) async {
    final res = await http.delete(Uri.parse('$_base/campaign/$campaignId'), headers: _headers(adminKey));
    if (res.statusCode != 200) throw _failure(res, 'delete campaign');
  }

  static Future<PromoteViyoDefaults> promoteViyoDefaults(String adminKey) async {
    final res = await http.get(Uri.parse('$_base/promote-viyo-defaults'), headers: _headers(adminKey));
    if (res.statusCode != 200) throw _failure(res, 'load Promote VIYO defaults');
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return PromoteViyoDefaults(
      targetName: data['target_name'] ?? 'VIYO',
      targetDescription: data['target_description'] ?? '',
      targetFeatures: ((data['target_features'] as List?) ?? []).map((e) => e.toString()).toList(),
      ctaText: data['cta_text'] ?? '',
    );
  }

  static Future<List<AdFormatInfo>> listFormats(String adminKey) async {
    final res = await http.get(Uri.parse('$_base/formats'), headers: _headers(adminKey));
    if (res.statusCode != 200) throw _failure(res, 'load ad formats');
    return (jsonDecode(res.body) as List)
        .map((e) => AdFormatInfo(key: e['key'] as String, label: e['label'] as String))
        .toList();
  }

  // --- Assets --------------------------------------------------------------

  static Future<AdAsset> uploadAsset(
    String adminKey,
    String campaignId,
    Uint8List bytes,
    String filename, {
    String assetType = 'reference',
  }) async {
    final uri = Uri.parse('$_base/campaign/$campaignId/assets?asset_type=$assetType');
    final request = http.MultipartRequest('POST', uri)
      ..headers['X-Admin-Key'] = adminKey
      ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename, contentType: _imageMediaType(filename)));
    final res = await http.Response.fromStream(await request.send());
    if (res.statusCode != 200) throw _failure(res, 'upload asset');
    return AdAsset.fromJson(jsonDecode(res.body));
  }

  static Future<List<AdAsset>> listAssets(String adminKey, String campaignId) async {
    final res = await http.get(Uri.parse('$_base/campaign/$campaignId/assets'), headers: _headers(adminKey));
    if (res.statusCode != 200) throw _failure(res, 'load assets');
    return (jsonDecode(res.body) as List).map((e) => AdAsset.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<void> deleteAsset(String adminKey, String assetId) async {
    final res = await http.delete(Uri.parse('$_base/asset/$assetId'), headers: _headers(adminKey));
    if (res.statusCode != 200) throw _failure(res, 'delete asset');
  }

  static Future<List<AdAsset>> listViyoAssetLibrary(String adminKey) async {
    final res = await http.get(Uri.parse('$_base/viyo-asset-library'), headers: _headers(adminKey));
    if (res.statusCode != 200) throw _failure(res, 'load the Viyo asset library');
    return (jsonDecode(res.body) as List).map((e) => AdAsset.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<AdAsset> uploadViyoLibraryAsset(String adminKey, Uint8List bytes, String filename, {String label = ''}) async {
    final uri = Uri.parse('$_base/viyo-asset-library?label=${Uri.encodeComponent(label)}');
    final request = http.MultipartRequest('POST', uri)
      ..headers['X-Admin-Key'] = adminKey
      ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename, contentType: _imageMediaType(filename)));
    final res = await http.Response.fromStream(await request.send());
    if (res.statusCode != 200) throw _failure(res, 'upload to the Viyo asset library');
    return AdAsset.fromJson(jsonDecode(res.body));
  }

  static Future<AdAsset> attachLibraryAsset(String adminKey, String campaignId, String libraryId) async {
    final res = await http.post(
      Uri.parse('$_base/campaign/$campaignId/assets/from-library/$libraryId'),
      headers: _headers(adminKey),
    );
    if (res.statusCode != 200) throw _failure(res, 'attach library asset');
    return AdAsset.fromJson(jsonDecode(res.body));
  }

  // --- Hook-First Engine -----------------------------------------------

  static Future<AdHookGenerationResult> generateHooks(String adminKey, String campaignId) async {
    final res = await http.post(Uri.parse('$_base/campaign/$campaignId/hooks'), headers: _headers(adminKey));
    if (res.statusCode != 200) throw _failure(res, 'generate hooks');
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return AdHookGenerationResult(
      hooks: (data['hooks'] as List).map((e) => AdHook.fromJson(e as Map<String, dynamic>)).toList(),
      recommendedFormat: data['recommended_format'] ?? '',
      costUsdCents: (data['cost_usd_cents'] as num?)?.toInt() ?? 0,
    );
  }

  static Future<List<AdHook>> listHooks(String adminKey, String campaignId) async {
    final res = await http.get(Uri.parse('$_base/campaign/$campaignId/hooks'), headers: _headers(adminKey));
    if (res.statusCode != 200) throw _failure(res, 'load hooks');
    return (jsonDecode(res.body) as List).map((e) => AdHook.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Pass hookId == 'auto' to select whichever candidate already ranked
  /// #1 — the "or let the system recommend one" path.
  static Future<AdCampaign> selectHook(String adminKey, String campaignId, String hookId) async {
    final res = await http.post(
      Uri.parse('$_base/campaign/$campaignId/hooks/$hookId/select'),
      headers: _headers(adminKey),
    );
    if (res.statusCode != 200) throw _failure(res, 'select hook');
    return AdCampaign.fromJson(jsonDecode(res.body));
  }

  // --- Script --------------------------------------------------------------

  static Future<AdScriptResult> generateScript(String adminKey, String campaignId) async {
    final res = await http.post(Uri.parse('$_base/campaign/$campaignId/script'), headers: _headers(adminKey));
    if (res.statusCode != 200) throw _failure(res, 'generate script');
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return AdScriptResult(
      scenes: (data['scenes'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList(),
      costUsdCents: (data['cost_usd_cents'] as num?)?.toInt() ?? 0,
    );
  }

  static Future<AdCampaign> saveScript(String adminKey, String campaignId, List<Map<String, dynamic>> scenes) async {
    final res = await http.put(
      Uri.parse('$_base/campaign/$campaignId/script'),
      headers: _headers(adminKey),
      body: jsonEncode({'scenes': scenes}),
    );
    if (res.statusCode != 200) throw _failure(res, 'save script');
    return AdCampaign.fromJson(jsonDecode(res.body));
  }

  // --- Generation ------------------------------------------------------

  static Future<AdJob> generateVideo(String adminKey, String campaignId) async {
    final res = await http.post(Uri.parse('$_base/campaign/$campaignId/generate'), headers: _headers(adminKey));
    if (res.statusCode != 200) throw _failure(res, 'start generation');
    return AdJob.fromJson(jsonDecode(res.body));
  }

  static Future<AdJob?> getLatestJob(String adminKey, String campaignId) async {
    final res = await http.get(Uri.parse('$_base/campaign/$campaignId/job'), headers: _headers(adminKey));
    if (res.statusCode != 200) throw _failure(res, 'check generation status');
    if (res.body == 'null' || res.body.isEmpty) return null;
    return AdJob.fromJson(jsonDecode(res.body));
  }

  // --- Performance -------------------------------------------------------

  static Future<void> recordPerformance(
    String adminKey,
    String campaignId, {
    String? hookId,
    double? retention1s,
    double? retention3s,
    double? retention5s,
    double? avgWatchSeconds,
    double? completionRate,
    double? ctr,
    int? installs,
    String notes = '',
  }) async {
    final res = await http.post(
      Uri.parse('$_base/campaign/$campaignId/performance'),
      headers: _headers(adminKey),
      body: jsonEncode({
        if (hookId != null) 'hook_id': hookId,
        if (retention1s != null) 'retention_1s': retention1s,
        if (retention3s != null) 'retention_3s': retention3s,
        if (retention5s != null) 'retention_5s': retention5s,
        if (avgWatchSeconds != null) 'avg_watch_seconds': avgWatchSeconds,
        if (completionRate != null) 'completion_rate': completionRate,
        if (ctr != null) 'ctr': ctr,
        if (installs != null) 'installs': installs,
        'notes': notes,
      }),
    );
    if (res.statusCode != 200) throw _failure(res, 'record performance');
  }

  static Future<List<Map<String, dynamic>>> listPerformance(String adminKey, String campaignId) async {
    final res = await http.get(Uri.parse('$_base/campaign/$campaignId/performance'), headers: _headers(adminKey));
    if (res.statusCode != 200) throw _failure(res, 'load performance records');
    return (jsonDecode(res.body) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }
}
