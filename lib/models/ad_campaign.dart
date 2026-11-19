/// One AI Ads Studio marketing-video project — mirrors backend
/// ads_studio.py's CampaignOut. Walks through draft -> hooks generated
/// -> hook selected -> script_ready -> generating -> ready/failed.
class AdCampaign {
  final String id;
  final String userId;
  final String promoteTarget; // viyo | ollie_ai | other_app | website
  final String targetName;
  final String targetDescription;
  final List<String> targetFeatures;
  final String targetAudience;
  final String objective;
  final String destinationLink;
  final String ctaText;
  final String? format;
  final String? recommendedFormat;
  final int durationSeconds;
  final String aspectRatio;
  final String resolution;
  final bool useVeo;
  final String veoTier; // lite | fast | standard
  final String? voiceGenderPreference;
  final String? voiceName;
  final String? selectedHookId;
  final List<Map<String, dynamic>>? script;
  final String status;
  final String? videoUrl;
  final String? bunnyVideoId;
  final String? thumbnailUrl;
  final int? durationActualSeconds;
  final int costUsdCents;
  final String? error;
  final String createdAt;
  /// The post-render check of the finished file: {"passed", "items": [{label, status, note}], ...}.
  final Map<String, dynamic>? qualityReport;
  /// A video that needs correction (never offered as a finished ad).
  final String? previewVideoUrl;

  // The product profile (universal Ads Maker). Facts are the advertiser's own word: the only claims an ad makes.
  final String brandName;
  final String? brandId; // My Brands: the saved brand this ad belongs to
  final String productSubtype;
  final Map<String, List<String>> facts; // features | benefits | prices | selling_points | specs
  final List<String> brandColors; // #RRGGBB
  final List<String> socialLinks;
  final Map<String, String> contact; // phone | email | address
  final String adStyle; // auto | product_cinematic | character | lifestyle | demo | social
  final String characterMode; // auto | custom | reuse | none
  final Map<String, dynamic> character;

  /// What the check found wrong, in plain words.
  List<String> get qualityProblems => [
        for (final i in (qualityReport?['items'] as List? ?? const []))
          if (i is Map && i['status'] == 'failed') '${i['label']}${(i['note'] ?? '').toString().isEmpty ? '' : ': ${i['note']}'}',
      ];

  const AdCampaign({
    required this.id,
    required this.userId,
    required this.promoteTarget,
    required this.targetName,
    required this.targetDescription,
    required this.targetFeatures,
    required this.targetAudience,
    required this.objective,
    required this.destinationLink,
    required this.ctaText,
    this.format,
    this.recommendedFormat,
    required this.durationSeconds,
    required this.aspectRatio,
    required this.resolution,
    required this.useVeo,
    this.veoTier = 'lite',
    this.voiceGenderPreference,
    this.voiceName,
    this.selectedHookId,
    this.script,
    required this.status,
    this.videoUrl,
    this.bunnyVideoId,
    this.thumbnailUrl,
    this.durationActualSeconds,
    required this.costUsdCents,
    this.error,
    this.qualityReport,
    this.previewVideoUrl,
    required this.createdAt,
    this.brandName = '',
    this.brandId,
    this.productSubtype = '',
    this.facts = const {},
    this.brandColors = const [],
    this.socialLinks = const [],
    this.contact = const {},
    this.adStyle = 'auto',
    this.characterMode = 'auto',
    this.character = const {},
  });

  bool get hasScript => script != null && script!.isNotEmpty;

  factory AdCampaign.fromJson(Map<String, dynamic> json) => AdCampaign(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        promoteTarget: json['promote_target'] ?? 'viyo',
        targetName: json['target_name'] ?? '',
        targetDescription: json['target_description'] ?? '',
        targetFeatures: ((json['target_features'] as List?) ?? []).map((e) => e.toString()).toList(),
        targetAudience: json['target_audience'] ?? '',
        objective: json['objective'] ?? '',
        destinationLink: json['destination_link'] ?? '',
        ctaText: json['cta_text'] ?? '',
        format: json['format'] as String?,
        recommendedFormat: json['recommended_format'] as String?,
        durationSeconds: (json['duration_seconds'] as num?)?.toInt() ?? 15,
        aspectRatio: json['aspect_ratio'] ?? '9:16',
        resolution: json['resolution'] ?? '720p',
        useVeo: json['use_veo'] == true,
        veoTier: json['veo_tier'] ?? 'lite',
        voiceGenderPreference: json['voice_gender_preference'] as String?,
        voiceName: json['voice_name'] as String?,
        selectedHookId: json['selected_hook_id'] as String?,
        script: (json['script'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList(),
        status: json['status'] ?? 'draft',
        videoUrl: json['video_url'] as String?,
        bunnyVideoId: json['bunny_video_id'] as String?,
        thumbnailUrl: json['thumbnail_url'] as String?,
        durationActualSeconds: (json['duration_actual_seconds'] as num?)?.toInt(),
        costUsdCents: (json['cost_usd_cents'] as num?)?.toInt() ?? 0,
        error: json['error'] as String?,
        createdAt: json['created_at'] ?? '',
        qualityReport: json['quality_report'] is Map ? Map<String, dynamic>.from(json['quality_report'] as Map) : null,
        previewVideoUrl: json['preview_video_url'] as String?,
        brandName: json['brand_name'] ?? '',
        brandId: json['brand_id'] as String?,
        productSubtype: json['product_subtype'] ?? '',
        facts: {
          if (json['facts'] is Map)
            for (final e in (json['facts'] as Map).entries)
              e.key.toString(): ((e.value as List?) ?? []).map((v) => v.toString()).toList(),
        },
        brandColors: ((json['brand_colors'] as List?) ?? []).map((e) => e.toString()).toList(),
        socialLinks: ((json['social_links'] as List?) ?? []).map((e) => e.toString()).toList(),
        contact: {
          if (json['contact'] is Map)
            for (final e in (json['contact'] as Map).entries)
              if (e.value != null) e.key.toString(): e.value.toString(),
        },
        adStyle: json['ad_style'] ?? 'auto',
        characterMode: json['character_mode'] ?? 'auto',
        character: json['character'] is Map ? Map<String, dynamic>.from(json['character'] as Map) : const {},
      );
}
