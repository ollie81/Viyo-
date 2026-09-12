import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';
import '../../constants/supabase_constants.dart';
import '../../models/coach_video_context.dart';
import '../../models/insufficient_coins_exception.dart';
import '../../models/post.dart';
import '../../services/post_service.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/guest_gate.dart';
import '../../widgets/insufficient_coins_sheet.dart';
import '../../widgets/upload_progress_card.dart';
import 'video_coach_screen.dart';

/// AI Repurposer — upload a longer video, get back up to 5 ranked
/// highlight clips (pick your favorite), each auto-cropped to 9:16 with
/// burned-in captions and dead air trimmed out.
///
/// Fix for "Broken pipe" error:
///   Previously the video was streamed directly to Railway via multipart,
///   which hit Railway's ~60s inbound proxy timeout during upload +
///   processing. Now we upload the raw video to Supabase Storage first
///   (bypassing Railway entirely), then send just the URL to the backend.
///   Railway only handles a small JSON request, so there is nothing to
///   time out during the upload phase.
///
/// Fix for "Token verification failed" error:
///   That was a backend bug (PyJWT 2.x requires algorithms= even with
///   verify_signature=False). Fixed in repurpose.py — no Flutter change
///   needed; the token was always correct on this side.
///
/// Fix for the processing call itself timing out on long videos:
///   /api/v1/repurpose now returns a job_id immediately instead of
///   blocking until every clip is rendered — with up to 5 clips per
///   video, the full pipeline (transcription + N renders + N thumbnail
///   picks) can take several minutes, longer than Railway will hold a
///   single request open. This screen now polls GET
///   /api/v1/repurpose/{job_id} until the job is done or failed instead
///   of waiting on one long HTTP call.
class AiRepurposeScreen extends StatefulWidget {
  const AiRepurposeScreen({super.key});

  @override
  State<AiRepurposeScreen> createState() => _AiRepurposeScreenState();
}

class _AiRepurposeScreenState extends State<AiRepurposeScreen> {
  File? _selectedVideo;
  bool _isUploading = false;
  bool _isProcessing = false;
  double _uploadProgress = 0;
  int _uploadTotalBytes = 0;
  String? _error;
  Map<String, dynamic>? _result;
  int _selectedClipIndex = 0;
  String? _videoId;
  bool _posting = false;

  Future<void> _pickVideo() async {
    setState(() => _error = null);
    final picked = await ImagePicker().pickVideo(source: ImageSource.gallery);
    if (picked != null) {
      setState(() {
        _selectedVideo = File(picked.path);
        _result = null;
        _videoId = null;
      });
    }
  }

  Future<void> _process() async {
    if (_selectedVideo == null) return;
    if (!await GuestGate.allow(context, action: 'use the AI Repurposer')) return;
    setState(() {
      _isUploading = true;
      _uploadProgress = 0;
      _error = null;
    });

    try {
      // Step 1: Upload the video to Supabase Storage.
      // This keeps large file data off Railway's inbound proxy, which
      // has a hard timeout that caused the "Broken pipe" error before.
      final userId = SupabaseService.currentUserId;
      if (userId == null) throw Exception('Not logged in');

      final ext = _selectedVideo!.path.split('.').last.toLowerCase();
      final storagePath = '$userId/${const Uuid().v4()}.$ext';

      _uploadTotalBytes = await _selectedVideo!.length();

      // Uses the progress-reporting upload rather than the plain
      // storage .upload(), which reports nothing — that's why the
      // percentage never moved off zero before.
      final videoUrl = await PostService.uploadMediaWithProgress(
        _selectedVideo!,
        userId,
        storagePath: storagePath,
        onProgress: (p) {
          if (mounted) setState(() => _uploadProgress = p);
        },
      );

      // This stable ID ties the Coach history to this exact uploaded video.
      _videoId = storagePath;

      setState(() {
        _isUploading = false;
        _isProcessing = true;
      });

      // Step 2: Start the repurpose job. This returns almost immediately
      // with a job_id — the actual transcription + rendering happens on
      // the server in the background, so this call is never at risk of
      // Railway's request-handling timeout no matter how long a video
      // takes to process.
      final token = SupabaseService.client.auth.currentSession?.accessToken;
      final startUri = Uri.parse('${AiBackendConstants.baseUrl}/api/v1/repurpose');

      final startResponse = await http.post(
        startUri,
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'video_url': videoUrl}),
      );

      if (startResponse.statusCode != 200) {
        final body = jsonDecode(startResponse.body);
        final detail = body['detail'];
        if (startResponse.statusCode == 402 && detail is Map) {
          throw InsufficientCoinsException(
            feature: detail['feature'] as String? ?? '',
            balance: (detail['balance'] as num?)?.toInt() ?? 0,
            needed: (detail['needed'] as num?)?.toInt() ?? 0,
          );
        }
        throw Exception(detail ?? 'Server returned ${startResponse.statusCode}');
      }

      final jobId = jsonDecode(startResponse.body)['job_id'] as String;

      // Step 3: Poll for the result instead of holding one HTTP
      // connection open — Whisper transcription plus up to 5 clip
      // renders can take several minutes on a long video.
      final statusUri = Uri.parse('${AiBackendConstants.baseUrl}/api/v1/repurpose/$jobId');
      const pollInterval = Duration(seconds: 4);
      const maxAttempts = 120; // ~8 minutes, generous for the longest allowed video

      Map<String, dynamic>? finalResult;
      for (var attempt = 0; attempt < maxAttempts; attempt++) {
        await Future.delayed(pollInterval);
        if (!mounted) return;

        final statusResponse = await http.get(
          statusUri,
          headers: {if (token != null) 'Authorization': 'Bearer $token'},
        );
        if (statusResponse.statusCode != 200) {
          final body = jsonDecode(statusResponse.body);
          throw Exception(body['detail'] ?? 'Server returned ${statusResponse.statusCode}');
        }

        final statusBody = jsonDecode(statusResponse.body);
        final status = statusBody['status'] as String?;
        if (status == 'done') {
          finalResult = statusBody['result'] as Map<String, dynamic>?;
          break;
        }
        if (status == 'failed') {
          throw Exception(statusBody['error'] ?? 'Processing failed');
        }
        // status == 'processing' — keep polling.
      }

      if (finalResult == null) {
        throw Exception(
          "Still processing after several minutes — this can happen on long videos. "
          "Check back in a bit; your clips may still finish.",
        );
      }

      setState(() {
        _result = finalResult;
        _selectedClipIndex = 0;
      });
    } on InsufficientCoinsException catch (e) {
      if (mounted) showInsufficientCoinsSheet(context, e);
    } catch (e) {
      setState(() => _error = 'Processing failed: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _isProcessing = false;
        });
      }
    }
  }

  Future<void> _postToFeed() async {
    final userId = SupabaseService.currentUserId;
    final clip = _selectedClip;
    if (userId == null || clip == null) return;
    if (!await GuestGate.allow(context, action: 'post')) return;

    setState(() => _posting = true);
    try {
      final videoUrl = clip['processed_video_url'] as String;
      final highlight = clip['highlight'] as Map<String, dynamic>?;
      final thumbnailUrl = clip['thumbnail_url'] as String?;

      // Prefer the generated ready-to-post caption over the short
      // title — the title is a label for picking between clips, the
      // caption is what's actually written to be posted.
      final caption = (highlight?['caption'] as String?)?.trim();
      final title = (highlight?['suggested_title'] as String?)?.trim() ?? '';
      final hashtags = ((highlight?['hashtags'] as List<dynamic>?) ?? const [])
          .map((t) => '#$t')
          .join(' ');
      final body = [
        (caption != null && caption.isNotEmpty) ? caption : title,
        if (hashtags.isNotEmpty) hashtags,
      ].where((s) => s.isNotEmpty).join('\n\n');

      await PostService.createPost(
        userId: userId,
        type: PostType.video,
        caption: body,
        mediaUrl: videoUrl,
        thumbnailUrl: thumbnailUrl,
        // Clips are variable length now (12-60s), so the real duration
        // has to come from the highlight rather than a hardcoded 60.
        durationSeconds: _selectedClipDurationSeconds,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Posted to your feed! 🎉')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = 'Could not post: $e');
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  String get _statusLabel {
    if (_isUploading) return 'Uploading video...';
    if (_isProcessing) return 'Processing (can take a few minutes)...';
    return 'Run AI Repurpose';
  }

  bool get _isBusy => _isUploading || _isProcessing;

  List<dynamic> get _clips => (_result?['clips'] as List<dynamic>?) ?? const [];

  Map<String, dynamic>? get _selectedClip =>
      _selectedClipIndex < _clips.length ? _clips[_selectedClipIndex] as Map<String, dynamic> : null;

  double get _deadAirRemoved =>
      (_selectedClip?['dead_air_removed_seconds'] as num?)?.toDouble() ?? 0.0;

  double get _fillerWordsRemovedSeconds =>
      (_selectedClip?['filler_words_removed_seconds'] as num?)?.toDouble() ?? 0.0;

  int get _fillerWordsRemovedCount =>
      (_selectedClip?['filler_words_removed_count'] as num?)?.toInt() ?? 0;

  String? get _quoteCardUrl => _selectedClip?['quote_card_url'] as String?;

  Map<String, dynamic>? get _feedback => _result?['feedback'] as Map<String, dynamic>?;

  String get _hookLine =>
      (_selectedClip?['highlight']?['hook_line'] as String?)?.trim() ?? '';

  String get _clipCaption =>
      (_selectedClip?['highlight']?['caption'] as String?)?.trim() ?? '';

  List<String> get _clipHashtags =>
      ((_selectedClip?['highlight']?['hashtags'] as List<dynamic>?) ?? const [])
          .map((t) => t.toString())
          .toList();

  /// Everything the analyzer measured about this video, packaged for the
  /// AI Coach.
  ///
  /// The Coach receives a storage path as its video_id, which matches no
  /// row in `posts` — so without this it has nothing to read and answers
  /// with generic advice about a video it has never seen. This is the
  /// transcript, the hook, the caption and the critique it just produced
  /// on this exact clip.
  CoachVideoContext get _coachContext => CoachVideoContext(
        transcript: (_result?['transcript'] as String?) ?? '',
        durationSeconds: _selectedClipDurationSeconds > 0
            ? _selectedClipDurationSeconds.toDouble()
            : null,
        hookLine: _hookLine,
        caption: _clipCaption,
        hashtags: _clipHashtags,
        verdict: (_feedback?['verdict'] as String?)?.trim() ?? '',
        issues: ((_feedback?['issues'] as List<dynamic>?) ?? const [])
            .map((i) => i.toString())
            .toList(),
        strengths: ((_feedback?['strengths'] as List<dynamic>?) ?? const [])
            .map((i) => i.toString())
            .toList(),
        footageScore: (_feedback?['score'] as num?)?.toInt(),
        wordsPerMinute: (_feedback?['words_per_minute'] as num?)?.toDouble(),
        silencePercent: (_feedback?['silence_percent'] as num?)?.toDouble(),
      );

  /// Clip length after dead-air AND filler-word trimming — both are cut
  /// from the render now, so both have to come off the reported length
  /// or this understates how much shorter the actual clip is.
  int get _selectedClipDurationSeconds {
    final highlight = _selectedClip?['highlight'] as Map<String, dynamic>?;
    final start = (highlight?['start_time'] as num?)?.toDouble();
    final end = (highlight?['end_time'] as num?)?.toDouble();
    if (start == null || end == null || end <= start) return 0;
    final trimmed = _deadAirRemoved + _fillerWordsRemovedSeconds;
    return (end - start - trimmed).round().clamp(1, 600);
  }

  Future<void> _copy(String label, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label copied')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: const Text('AI Repurposer'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Upload a longer video — the AI finds up to 3 ranked highlight '
              'clips, each cropped to 9:16 with burned-in captions and dead '
              'air trimmed out.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 6),
            const Text(
              'Limits: configured by the backend/storage plan. The Coach keeps a separate history for each video.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 11),
            ),
            const SizedBox(height: 20),

            GestureDetector(
              onTap: _isBusy ? null : _pickVideo,
              child: Container(
                height: 180,
                decoration: AppTheme.card(),
                child: _selectedVideo == null
                    ? const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.video_library_outlined, size: 40, color: AppColors.primary),
                            SizedBox(height: 10),
                            Text('Tap to select a video', style: TextStyle(color: AppColors.textSecondary)),
                          ],
                        ),
                      )
                    : Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.check_circle, size: 36, color: AppColors.success),
                            const SizedBox(height: 8),
                            Text(
                              _selectedVideo!.path.split('/').last,
                              style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
              ),
            ),
            if (_isBusy) ...[
              const SizedBox(height: 16),
              UploadProgressCard(
                uploading: _isUploading,
                progress: _uploadProgress,
                totalBytes: _uploadTotalBytes,
              ),
            ],

            const SizedBox(height: 16),

            ElevatedButton(
              onPressed: (_selectedVideo == null || _isBusy) ? null : _process,
              child: _isBusy
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                        const SizedBox(width: 12),
                        Text(_statusLabel),
                      ],
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('Run AI Repurpose'),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.monetization_on, size: 13, color: Colors.white),
                              const SizedBox(width: 3),
                              Text(
                                '${FeatureCoinCosts.repurpose}',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
            ),

            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
            ],

            if (_feedback != null) ...[
              const SizedBox(height: 24),
              _VideoFeedbackCard(feedback: _feedback!),
            ],

            if (_clips.isNotEmpty) ...[
              const SizedBox(height: 24),
              if (_clips.length > 1) ...[
                const Text(
                  'Pick a clip — ranked best first',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 72,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _clips.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) {
                      final clip = _clips[i] as Map<String, dynamic>;
                      final score = (clip['highlight']?['score'] as num?)?.toInt() ?? 0;
                      final thumbUrl = clip['thumbnail_url'] as String?;
                      final selected = i == _selectedClipIndex;
                      return GestureDetector(
                        onTap: () => setState(() => _selectedClipIndex = i),
                        child: Container(
                          width: 108,
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: selected ? AppColors.primary.withOpacity(0.15) : AppColors.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: selected ? AppColors.primary : AppColors.surfaceBorder,
                            ),
                          ),
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: SizedBox(
                                  width: 34,
                                  height: 56,
                                  child: thumbUrl != null
                                      ? Image.network(
                                          thumbUrl,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) => Container(
                                            color: AppColors.surfaceBorder,
                                            child: const Icon(Icons.movie_outlined, size: 14, color: AppColors.textMuted),
                                          ),
                                        )
                                      : Container(
                                          color: AppColors.surfaceBorder,
                                          child: const Icon(Icons.movie_outlined, size: 14, color: AppColors.textMuted),
                                        ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      'Clip ${i + 1}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: selected ? AppColors.primary : AppColors.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Score $score',
                                      style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Container(
                padding: const EdgeInsets.all(16),
                decoration: AppTheme.card(borderColor: AppColors.primary.withOpacity(0.4)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _selectedClip?['highlight']?['suggested_title'] ?? 'Clip ready',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _selectedClip?['highlight']?['reason'] ?? '',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                    if (_hookLine.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(11),
                        decoration: BoxDecoration(
                          color: AppColors.coin.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.coin.withOpacity(0.3)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.bolt, size: 13, color: AppColors.coin),
                                const SizedBox(width: 5),
                                Text(
                                  'HOOK — FIRST 2 SECONDS',
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    letterSpacing: 0.8,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.coin.withOpacity(0.95),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '"$_hookLine"',
                              style: const TextStyle(
                                fontSize: 13,
                                height: 1.35,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Burned across the top of the clip so it lands before anyone scrolls.',
                              style: TextStyle(fontSize: 10.5, color: AppColors.textMuted, height: 1.3),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (_clipCaption.isNotEmpty || _clipHashtags.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          const Text(
                            'READY TO POST',
                            style: TextStyle(
                              fontSize: 9.5,
                              letterSpacing: 0.8,
                              color: AppColors.textMuted,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const Spacer(),
                          GestureDetector(
                            onTap: () => _copy(
                              'Caption',
                              [
                                _clipCaption,
                                if (_clipHashtags.isNotEmpty)
                                  _clipHashtags.map((t) => '#$t').join(' '),
                              ].where((s) => s.isNotEmpty).join('\n\n'),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.copy_rounded, size: 13, color: AppColors.primary),
                                SizedBox(width: 4),
                                Text(
                                  'Copy',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 7),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(11),
                        decoration: BoxDecoration(
                          color: AppColors.background.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.surfaceBorder),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_clipCaption.isNotEmpty)
                              Text(
                                _clipCaption,
                                style: const TextStyle(fontSize: 12.5, height: 1.4),
                              ),
                            if (_clipHashtags.isNotEmpty) ...[
                              if (_clipCaption.isNotEmpty) const SizedBox(height: 8),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: _clipHashtags
                                    .map((tag) => Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: AppColors.primary.withOpacity(0.12),
                                            borderRadius: BorderRadius.circular(999),
                                          ),
                                          child: Text(
                                            '#$tag',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: AppColors.primary,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ))
                                    .toList(),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                    if (_deadAirRemoved > 0.3 || _fillerWordsRemovedCount > 0) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (_deadAirRemoved > 0.3)
                            _TrimPill(
                              icon: Icons.content_cut,
                              label: 'Trimmed ${_deadAirRemoved.toStringAsFixed(1)}s of dead air',
                            ),
                          if (_fillerWordsRemovedCount > 0)
                            _TrimPill(
                              icon: Icons.record_voice_over_outlined,
                              label: _fillerWordsRemovedCount == 1
                                  ? 'Removed 1 filler word ("um", "uh"...)'
                                  : 'Removed $_fillerWordsRemovedCount filler words',
                            ),
                        ],
                      ),
                    ],
                    if (_quoteCardUrl != null) ...[
                      const SizedBox(height: 14),
                      const Text(
                        'Quote card',
                        style: TextStyle(fontSize: 11, color: AppColors.textMuted, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: Image.network(_quoteCardUrl!, fit: BoxFit.cover),
                        ),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () => Share.share(_quoteCardUrl!),
                        icon: const Icon(Icons.share_outlined, size: 16),
                        label: const Text('Share Quote Card'),
                      ),
                    ],
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _posting ? null : _postToFeed,
                      child: Text(
                        _posting
                            ? 'Posting...'
                            : _selectedClipDurationSeconds > 0
                                ? 'Post This ${_selectedClipDurationSeconds}s Clip to My Feed'
                                : 'Post This Clip to My Feed',
                      ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _videoId == null
                          ? null
                          : () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => VideoCoachScreen(
                                    videoId: _videoId!,
                                    videoContext: _coachContext,
                                  ),
                                ),
                              );
                            },
                      icon: const Icon(Icons.auto_awesome),
                      label: const Text('Open AI Coach'),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// An honest read on the SOURCE footage, not the clips cut from it.
///
/// Every other tool in this space quietly returns weak clips when the
/// footage is weak, leaving the creator guessing why nothing lands.
/// The numbers along the bottom are measured server-side (see
/// viyo_ai's _measure_video_signals), so the critique cites evidence
/// instead of asking anyone to trust a vibe.
class _VideoFeedbackCard extends StatelessWidget {
  final Map<String, dynamic> feedback;

  const _VideoFeedbackCard({required this.feedback});

  int get _score => (feedback['score'] as num?)?.toInt() ?? 0;

  String get _verdict => (feedback['verdict'] as String?)?.trim() ?? '';

  List<String> get _issues =>
      ((feedback['issues'] as List<dynamic>?) ?? const [])
          .map((e) => e.toString())
          .where((e) => e.isNotEmpty)
          .toList();

  List<String> get _strengths =>
      ((feedback['strengths'] as List<dynamic>?) ?? const [])
          .map((e) => e.toString())
          .where((e) => e.isNotEmpty)
          .toList();

  Color get _scoreColor {
    if (_score >= 70) return AppColors.success;
    if (_score >= 45) return AppColors.coin;
    return AppColors.danger;
  }

  @override
  Widget build(BuildContext context) {
    final wpm = (feedback['words_per_minute'] as num?)?.toDouble() ?? 0;
    final silence = (feedback['silence_percent'] as num?)?.toDouble() ?? 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.card(borderColor: _scoreColor.withOpacity(0.35)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.insights_rounded, size: 17, color: _scoreColor),
              const SizedBox(width: 7),
              const Expanded(
                child: Text(
                  'Your footage, honestly',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: _scoreColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: _scoreColor.withOpacity(0.4)),
                ),
                child: Text(
                  '$_score/100',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: _scoreColor,
                  ),
                ),
              ),
            ],
          ),
          if (_verdict.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              _verdict,
              style: const TextStyle(fontSize: 13, height: 1.4),
            ),
          ],
          if (_issues.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text(
              'FIX NEXT TIME',
              style: TextStyle(
                fontSize: 9.5,
                letterSpacing: 0.8,
                color: AppColors.textMuted,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 7),
            ..._issues.map((issue) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Icon(Icons.arrow_right_rounded,
                            size: 16, color: AppColors.danger),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          issue,
                          style: const TextStyle(
                            fontSize: 12.5,
                            height: 1.35,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                )),
          ],
          if (_strengths.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text(
              'KEEP DOING',
              style: TextStyle(
                fontSize: 9.5,
                letterSpacing: 0.8,
                color: AppColors.textMuted,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 7),
            ..._strengths.map((s) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Icon(Icons.check_rounded,
                            size: 14, color: AppColors.success),
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          s,
                          style: const TextStyle(
                            fontSize: 12.5,
                            height: 1.35,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                )),
          ],
          if (wpm > 0 || silence > 0) ...[
            const SizedBox(height: 12),
            const Divider(color: AppColors.surfaceBorder, height: 1),
            const SizedBox(height: 10),
            Row(
              children: [
                if (wpm > 0)
                  Expanded(
                    child: _Metric(
                      label: 'Speaking pace',
                      value: '${wpm.round()} wpm',
                      // Short-form delivery generally lands between 150
                      // and 190 words per minute.
                      good: wpm >= 150 && wpm <= 190,
                    ),
                  ),
                if (silence > 0)
                  Expanded(
                    child: _Metric(
                      label: 'Dead air',
                      value: '${silence.round()}%',
                      good: silence <= 20,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  final bool good;

  const _Metric({required this.label, required this.value, required this.good});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 9,
            letterSpacing: 0.6,
            color: AppColors.textMuted,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 3),
        Row(
          children: [
            Text(
              value,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
            ),
            const SizedBox(width: 5),
            Icon(
              good ? Icons.check_circle_rounded : Icons.error_outline_rounded,
              size: 13,
              color: good ? AppColors.success : AppColors.coin,
            ),
          ],
        ),
      ],
    );
  }
}

/// One "what got trimmed" pill — dead air and filler words are reported
/// as separate lines (see the fields on RepurposeClipResult) since
/// they're different edits with different causes, but they share the
/// exact same look so the pair reads as one family of info.
class _TrimPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _TrimPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.success.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.success.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.success),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.success,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
