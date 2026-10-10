import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';
import '../../../models/ad_campaign.dart';
import '../../../services/ads_studio_service.dart';
import '../../../services/bunny_stream_service.dart';
import '../../../services/web_download_stub.dart'
    if (dart.library.html) '../../../services/web_download_html.dart' as web_download;
import '../../../theme/app_theme.dart';
import 'ads_studio_wizard_screen.dart';

/// Final step — preview, download, regenerate, or record real
/// performance numbers once they're known. Regenerating just reopens
/// the wizard on this same campaign so every earlier choice (assets,
/// hook, script) is still there to adjust rather than start from zero.
class AdsResultScreen extends StatefulWidget {
  final String adminKey;
  final String campaignId;
  const AdsResultScreen({super.key, required this.adminKey, required this.campaignId});

  @override
  State<AdsResultScreen> createState() => _AdsResultScreenState();
}

class _AdsResultScreenState extends State<AdsResultScreen> {
  bool _loading = true;
  String? _error;
  AdCampaign? _campaign;
  VideoPlayerController? _videoController;
  bool _downloading = false;
  // True while we're polling Bunny for transcode completion, and also
  // the sticky "still processing" state if it never finished within
  // waitForReady's timeout — in either case we must not hand a
  // not-yet-ready URL to VideoPlayerController, which fails hard with
  // MEDIA_ERR_SRC_NOT_SUPPORTED rather than a retriable error.
  bool _processingVideo = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _processingVideo = false;
    });
    try {
      final campaign = await AdsStudioService.getCampaign(widget.adminKey, widget.campaignId);
      String? playbackUrl = campaign.videoUrl;
      // Bunny transcodes every upload before it's playable (same race
      // already solved for Viyo Studio's publish flow) — wait for that
      // to finish rather than handing the browser/video_player a URL
      // that 404s or comes back in a container it rejects outright.
      if (campaign.bunnyVideoId != null) {
        if (!mounted) return;
        setState(() => _processingVideo = true);
        BunnyVideoStatus? status;
        try {
          status = await BunnyStreamService.waitForReady(campaign.bunnyVideoId!);
        } on BunnyNotConfiguredException {
          status = null;
        }
        if (!mounted) return;
        if (status != null && status.failed) {
          throw Exception('Bunny could not process this video.');
        }
        if (status != null && status.ready) {
          playbackUrl = status.playbackUrl.isNotEmpty ? status.playbackUrl : playbackUrl;
          setState(() => _processingVideo = false);
        } else {
          // Timed out still processing, or Bunny isn't configured and
          // we have no other way to confirm readiness — don't attempt
          // playback yet; leave _processingVideo set so the UI shows a
          // retry affordance instead of a broken player.
          playbackUrl = null;
        }
      }
      if (playbackUrl != null) {
        final controller = VideoPlayerController.networkUrl(Uri.parse(playbackUrl));
        await controller.initialize();
        if (!mounted) return;
        await _videoController?.dispose();
        _videoController = controller;
      }
      if (!mounted) return;
      setState(() => _campaign = campaign);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
        _processingVideo = false;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _download() async {
    final campaign = _campaign;
    if (campaign?.videoUrl == null) return;
    setState(() => _downloading = true);
    try {
      final res = await http.get(Uri.parse(campaign!.videoUrl!));
      if (res.statusCode != 200) throw Exception('Could not download video (${res.statusCode})');
      final fileName = '${campaign.targetName.replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_')}_ad.mp4';
      if (kIsWeb) {
        web_download.downloadBytesWeb(res.bodyBytes, fileName);
      } else {
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/$fileName');
        await file.writeAsBytes(res.bodyBytes);
        if (!mounted) return;
        await Share.shareXFiles([XFile(file.path)], text: fileName);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst(RegExp(r'^Exception:\s*'), ''))));
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  void _regenerate() {
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => AdsStudioWizardScreen(adminKey: widget.adminKey, preselectedCampaignId: widget.campaignId),
    ));
  }

  Future<void> _recordPerformance() async {
    final retention1 = TextEditingController();
    final retention3 = TextEditingController();
    final completion = TextEditingController();
    final ctr = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Record performance'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: retention1, decoration: const InputDecoration(labelText: '1s retention %'), keyboardType: TextInputType.number),
            TextField(controller: retention3, decoration: const InputDecoration(labelText: '3s retention %'), keyboardType: TextInputType.number),
            TextField(controller: completion, decoration: const InputDecoration(labelText: 'Completion rate %'), keyboardType: TextInputType.number),
            TextField(controller: ctr, decoration: const InputDecoration(labelText: 'CTR %'), keyboardType: TextInputType.number),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (saved != true) return;
    try {
      await AdsStudioService.recordPerformance(
        widget.adminKey,
        widget.campaignId,
        retention1s: double.tryParse(retention1.text),
        retention3s: double.tryParse(retention3.text),
        completionRate: double.tryParse(completion.text),
        ctr: double.tryParse(ctr.text),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved — manually entered, not a live platform integration.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst(RegExp(r'^Exception:\s*'), ''))));
    }
  }

  /// Requested vs. actual runtime — Veo only renders in fixed 4/6/8s
  /// clip lengths and TTS dialogue can run long, so the assembled
  /// video can drift from what was asked for. Surfacing the real
  /// number here (rather than only the campaign's requested setting)
  /// is the validation step the admin can actually act on.
  Widget _durationNote(AdCampaign campaign) {
    final requested = campaign.durationSeconds;
    final actual = campaign.durationActualSeconds!;
    final driftSeconds = (actual - requested).abs();
    final isOff = driftSeconds > 3 && driftSeconds > requested * 0.25;
    return Row(
      children: [
        Icon(isOff ? Icons.warning_amber_rounded : Icons.timer_outlined, size: 14, color: isOff ? AppColors.danger : AppColors.textMuted),
        const SizedBox(width: 6),
        Text(
          isOff
              ? 'Requested ${requested}s — came out ${actual}s'
              : 'Requested ${requested}s • Actual ${actual}s',
          style: TextStyle(fontSize: 12, color: isOff ? AppColors.danger : AppColors.textMuted, fontWeight: isOff ? FontWeight.w700 : FontWeight.normal),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final campaign = _campaign;
    return Scaffold(
      appBar: AppBar(backgroundColor: AppColors.background, title: const Text('Ad result')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null || campaign == null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error ?? 'Not found', style: const TextStyle(color: AppColors.danger))))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  children: [
                    if (campaign.status == 'failed') ...[
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: AppTheme.card(borderColor: AppColors.danger),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Generation failed', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.danger)),
                            const SizedBox(height: 6),
                            Text(campaign.error ?? 'Unknown error.', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ] else if (_processingVideo) ...[
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: AppTheme.card(),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                                SizedBox(width: 10),
                                Text('Still processing', style: TextStyle(fontWeight: FontWeight.w800)),
                              ],
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Bunny is still processing the video — it usually takes a few minutes after generation finishes. '
                              'Tap refresh to check again.',
                              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                            ),
                            const SizedBox(height: 10),
                            OutlinedButton.icon(
                              onPressed: _load,
                              icon: const Icon(Icons.refresh, size: 16),
                              label: const Text('Refresh'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ] else if (_videoController != null && _videoController!.value.isInitialized)
                      // Capped well below full screen height so the download/
                      // edit/record buttons below are always visible without
                      // scrolling — a full-bleed 9:16 video was filling the
                      // entire viewport on phones, making those actions look
                      // like they didn't exist at all.
                      ConstrainedBox(
                        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
                        child: Center(
                          child: AspectRatio(
                            aspectRatio: _videoController!.value.aspectRatio,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  VideoPlayer(_videoController!),
                                  GestureDetector(
                                    onTap: () => setState(() => _videoController!.value.isPlaying ? _videoController!.pause() : _videoController!.play()),
                                    child: AnimatedBuilder(
                                      animation: _videoController!,
                                      builder: (_, __) => _videoController!.value.isPlaying
                                          ? const SizedBox.shrink()
                                          : Container(color: Colors.black26, child: const Icon(Icons.play_arrow, size: 54, color: Colors.white)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (campaign.status == 'ready' && campaign.durationActualSeconds != null) ...[
                      const SizedBox(height: 10),
                      _durationNote(campaign),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: campaign.videoUrl == null || _processingVideo || _downloading ? null : _download,
                            icon: _downloading
                                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.download_outlined, size: 16),
                            label: Text(_downloading ? 'Saving...' : 'Download'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _regenerate,
                            icon: const Icon(Icons.edit_outlined, size: 16),
                            label: const Text('Edit / regenerate'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _recordPerformance,
                        icon: const Icon(Icons.insights_outlined, size: 16),
                        label: const Text('Record performance (manual)'),
                      ),
                    ),
                  ],
                ),
    );
  }
}
