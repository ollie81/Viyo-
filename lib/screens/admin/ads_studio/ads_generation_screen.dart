import 'dart:async';
import 'package:flutter/material.dart';
import '../../../models/ad_job.dart';
import '../../../services/ads_studio_service.dart';
import '../../../theme/app_theme.dart';
import 'ads_result_screen.dart';

/// Kicks off the real video-generation background job and polls its
/// status — same shape as the Bunny-processing-status polling already
/// used elsewhere in the app (video_feed_screen.dart). Retrying after a
/// failure just calls generate again; the script/assets/hooks that
/// drove the failed attempt are untouched, so nothing is lost.
class AdsGenerationScreen extends StatefulWidget {
  final String adminKey;
  final String campaignId;
  const AdsGenerationScreen({super.key, required this.adminKey, required this.campaignId});

  @override
  State<AdsGenerationScreen> createState() => _AdsGenerationScreenState();
}

class _AdsGenerationScreenState extends State<AdsGenerationScreen> {
  AdJob? _job;
  String? _error;
  Timer? _timer;
  bool _starting = true;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _starting = true;
      _error = null;
    });
    try {
      final job = await AdsStudioService.generateVideo(widget.adminKey, widget.campaignId);
      if (!mounted) return;
      setState(() => _job = job);
      _timer = Timer.periodic(const Duration(seconds: 3), (_) => _poll());
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), ''));
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _poll() async {
    try {
      final job = await AdsStudioService.getLatestJob(widget.adminKey, widget.campaignId);
      if (!mounted || job == null) return;
      setState(() => _job = job);
      if (job.status == 'succeeded') {
        _timer?.cancel();
        if (!mounted) return;
        Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => AdsResultScreen(adminKey: widget.adminKey, campaignId: widget.campaignId),
        ));
      } else if (job.status == 'failed') {
        _timer?.cancel();
      }
    } catch (_) {
      // A transient poll failure isn't worth surfacing — the next tick retries.
    }
  }

  @override
  Widget build(BuildContext context) {
    final job = _job;
    return Scaffold(
      appBar: AppBar(backgroundColor: AppColors.background, title: const Text('Generating')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_starting)
                const CircularProgressIndicator()
              else if (_error != null) ...[
                const Icon(Icons.error_outline, color: AppColors.danger, size: 40),
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: AppColors.danger), textAlign: TextAlign.center),
                const SizedBox(height: 16),
                ElevatedButton(onPressed: _start, child: const Text('Retry')),
              ] else if (job != null && job.status == 'failed') ...[
                const Icon(Icons.error_outline, color: AppColors.danger, size: 40),
                const SizedBox(height: 12),
                Text(job.error ?? 'Generation failed.', style: const TextStyle(color: AppColors.danger), textAlign: TextAlign.center),
                const SizedBox(height: 16),
                ElevatedButton(onPressed: _start, child: const Text('Retry')),
              ] else if (job != null) ...[
                SizedBox(
                  width: 72,
                  height: 72,
                  child: CircularProgressIndicator(value: job.progressPct / 100, strokeWidth: 5),
                ),
                const SizedBox(height: 16),
                Text('${job.progressPct}%', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                const SizedBox(height: 8),
                const Text(
                  'Generating scenes, voiceover, captions and assembling the video — this can take a few minutes.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
