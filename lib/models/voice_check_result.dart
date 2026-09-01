class VoiceCheckResult {
  final bool hasVoiceProfile;
  final bool? consistent;
  final String? reason;
  final String? suggestedRewrite;

  VoiceCheckResult({
    required this.hasVoiceProfile,
    this.consistent,
    this.reason,
    this.suggestedRewrite,
  });

  factory VoiceCheckResult.fromJson(Map<String, dynamic> json) => VoiceCheckResult(
        hasVoiceProfile: json['has_voice_profile'] == true,
        consistent: json['consistent'] as bool?,
        reason: json['reason'] as String?,
        suggestedRewrite: json['suggested_rewrite'] as String?,
      );
}
