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
    required this.createdAt,
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
      );
}
