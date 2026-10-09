/// Status of a campaign's background video-generation run — polled by
/// [AdsGenerationScreen] the same way the app already polls a Bunny
/// video's processing status elsewhere.
class AdJob {
  final String id;
  final String campaignId;
  final String stage;
  final String status; // pending | running | succeeded | failed
  final int progressPct;
  final String? error;

  const AdJob({
    required this.id,
    required this.campaignId,
    required this.stage,
    required this.status,
    required this.progressPct,
    this.error,
  });

  bool get isDone => status == 'succeeded' || status == 'failed';

  factory AdJob.fromJson(Map<String, dynamic> json) => AdJob(
        id: json['id'] as String,
        campaignId: json['campaign_id'] as String,
        stage: json['stage'] ?? 'video',
        status: json['status'] ?? 'pending',
        progressPct: (json['progress_pct'] as num?)?.toInt() ?? 0,
        error: json['error'] as String?,
      );
}
