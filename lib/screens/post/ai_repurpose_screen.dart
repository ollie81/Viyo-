import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import '../../constants/supabase_constants.dart';
import '../../models/coach_video_context.dart';
import '../../models/insufficient_coins_exception.dart';
import '../../models/post.dart';
import '../../services/post_service.dart';
import '../../services/bunny_stream_service.dart';
import '../../services/repurpose_service.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/clip_preview_player.dart';
import '../../widgets/guest_gate.dart';
import '../../widgets/insufficient_coins_sheet.dart';
import '../../widgets/upload_progress_card.dart';
import '../../utils/friendly_error.dart';
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
  /// Opens the results of an earlier job, e.g. from a "clips ready" notification.
  final String? openJobId;
  const AiRepurposeScreen({super.key, this.openJobId});

  @override
  State<AiRepurposeScreen> createState() => _AiRepurposeScreenState();
}

class _AiRepurposeScreenState extends State<AiRepurposeScreen> {
  // XFile, not dart:io's File — see create_post_screen.dart's
  // _mediaFile for why (File doesn't work on web).
  XFile? _selectedVideo;
  bool _isUploading = false;
  bool _isProcessing = false;
  double _uploadProgress = 0;
  int _uploadTotalBytes = 0;
  String? _error;
  // Technical reason from the server for a failed job (which moments were
  // considered and why each was dropped), shown small so it can be shared.
  String? _errorDetail;
  Map<String, dynamic>? _result;
  int _selectedClipIndex = 0;
  String? _videoId;
  bool _posting = false;
  bool _sharing = false;
  // Live stage text from the worker ("Transcribing (40%)", "Editing
  // clip 2 of 5", "Waiting for a processing slot"...).
  String? _serverMessage;
  double? _serverProgress;

  // Optional — only used server-side when the video has no usable
  // speech (silent, or music/ambient audio with nothing to
  // transcribe). A normal video with speech ignores this entirely.
  final _promptController = TextEditingController();

  // Preferred clip length. A target for the AI, not a hard cut: a moment
  // that needs a little longer to land its hook and payoff keeps it.
  String _clipLength = 'auto';
  // How many shorts to make: 0 = as many as the video supports (up to 6).
  int _clipCount = 0;
  static const _clipLengths = [
    ('auto', 'Auto', 'The AI picks the best length for each moment.'),
    ('short', 'Short', 'About 15–30 seconds, 40 at most unless it\'s a standout moment.'),
    ('medium', 'Medium', 'About 30–45 seconds, 55 at most unless it\'s a standout moment.'),
    ('long', 'Long', 'About 45–60 seconds.'),
  ];

  // Downloads and shares carry a small "Made with Viyo" tag unless turned
  // off. Clips posted inside Viyo are never tagged.
  bool _addViyoTag = true;
  String? _jobId;
  final Map<String, String> _taggedUrls = {};
  // Which version to share or download: '' = the standard clip (fits every app), or one platform.
  String _platform = '';
  // Versions the creator made by switching edits, per clip index: {version, url, edits, quality}.
  final Map<int, Map<String, dynamic>> _versions = {};
  bool _applying = false;
  final Map<String, String> _platformUrls = {};

  // Free first video. Guests see it as free too: a new account gets it.
  RepurposeFreeTrial? _freeTrial;
  bool get _isFree => SupabaseService.isGuest || (_freeTrial?.eligible ?? false);
  int get _freeMaxMinutes => _freeTrial?.maxMinutes ?? 10;

  @override
  void initState() {
    super.initState();
    _refreshFreeTrial();
    final jobId = widget.openJobId;
    if (jobId != null) _openJob(jobId);
  }

  /// Shows a finished job's clips (or why it failed) without uploading again.
  Future<void> _openJob(String jobId) async {
    setState(() {
      _isProcessing = true;
      _serverMessage = 'Loading your clips';
      _error = null;
    });
    try {
      final token = SupabaseService.client.auth.currentSession?.accessToken;
      final res = await http.get(
        Uri.parse('${AiBackendConstants.baseUrl}/api/v1/repurpose/$jobId'),
        headers: {if (token != null) 'Authorization': 'Bearer $token'},
      );
      final body = jsonDecode(res.body);
      if (res.statusCode != 200) throw Exception(body['detail'] ?? 'Could not load these clips');
      final status = body['status'] as String?;
      if (!mounted) return;
      setState(() {
        if (status == 'done' && body['result'] != null) {
          _jobId = jobId;
          _taggedUrls.clear();
          _platformUrls.clear();
          _versions.clear();
          _result = body['result'] as Map<String, dynamic>;
          _selectedClipIndex = 0;
        } else if (status == 'failed') {
          _error = body['error'] as String? ?? 'This job failed.';
        } else {
          _error = "These clips are still being made. We'll notify you when they're ready.";
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = friendlyErrorMessage(e));
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _refreshFreeTrial() async {
    final status = await RepurposeService.freeTrialStatus();
    if (mounted) setState(() => _freeTrial = status);
  }

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  Future<void> _pickVideo() async {
    setState(() => _error = null);
    final picked = await ImagePicker().pickVideo(source: ImageSource.gallery);
    if (picked != null) {
      setState(() {
        _selectedVideo = picked;
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
      _errorDetail = null;
    });

    try {
      final userId = SupabaseService.currentUserId;
      if (userId == null) throw Exception('Not logged in');

      // Step 1: upload to a private, server-chosen path in Supabase
      // Storage (not the public posts bucket, and never through Railway).
      _uploadTotalBytes = await _selectedVideo!.length();
      String sourcePath;
      var viaBunny = false;
      if (_uploadTotalBytes > RepurposeService.supabaseUploadCapBytes) {
        // Too big for the storage plan's upload cap: send it to Bunny
        // Stream, wait for Bunny to prepare it, and let the server pull
        // it from there.
        final bunnyTicket = await RepurposeService.requestBunnyUpload(sizeBytes: _uploadTotalBytes);
        await BunnyStreamService.uploadVideo(
          _selectedVideo!,
          bunnyTicket.credentials,
          onProgress: (p) {
            if (mounted) setState(() => _uploadProgress = p);
          },
        );
        if (mounted) setState(() => _serverMessage = 'Preparing your video…');
        final prepared = await BunnyStreamService.waitForReady(
          bunnyTicket.credentials.videoId,
          timeout: const Duration(minutes: 30),
        );
        if (prepared == null) {
          throw Exception('Your video is still being prepared. Please try again in a few minutes.');
        }
        if (prepared.failed) {
          throw Exception('We couldn\'t process that video. Try a different file.');
        }
        sourcePath = bunnyTicket.sourcePath;
        viaBunny = true;
      } else {
        final contentType = RepurposeService.contentTypeFor(_selectedVideo!);
        final ticket = await RepurposeService.requestUpload(
          contentType: contentType,
          sizeBytes: _uploadTotalBytes,
        );
        await RepurposeService.uploadSource(
          _selectedVideo!,
          ticket,
          contentType,
          onProgress: (p) {
            if (mounted) setState(() => _uploadProgress = p);
          },
        );
        sourcePath = ticket.sourcePath;
      }

      // This stable ID ties the Coach history to this exact uploaded video.
      _videoId = sourcePath;

      setState(() {
        _isUploading = false;
        _isProcessing = true;
        _serverMessage = null;
        _serverProgress = null;
      });

      // Step 2: start the job. Returns immediately; the worker service
      // does the processing. The same client_request_id is re-sent if the
      // request drops, so a flaky connection can never charge twice.
      final token = SupabaseService.client.auth.currentSession?.accessToken;
      final startUri = Uri.parse('${AiBackendConstants.baseUrl}/api/v1/repurpose');
      final requestId = const Uuid().v4();
      final startBody = jsonEncode({
        'source_path': sourcePath,
        if (viaBunny) 'source': 'bunny',
        'client_request_id': requestId,
        if (_clipLength != 'auto') 'clip_length': _clipLength,
        if (_clipCount > 0) 'clip_count': _clipCount,
        if (_promptController.text.trim().isNotEmpty)
          'creative_prompt': _promptController.text.trim(),
      });

      http.Response? startResponse;
      for (var attempt = 0; attempt < 3 && startResponse == null; attempt++) {
        try {
          startResponse = await http.post(
            startUri,
            headers: {
              'Content-Type': 'application/json',
              if (token != null) 'Authorization': 'Bearer $token',
            },
            body: startBody,
          );
        } catch (_) {
          if (attempt == 2) rethrow;
          await Future.delayed(Duration(seconds: 2 * (attempt + 1)));
        }
      }

      if (startResponse!.statusCode != 200) {
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
      _jobId = jobId;
      _taggedUrls.clear();
      _platformUrls.clear();
      _versions.clear();

      // Step 3: poll. A long video can wait in the queue and then take
      // several minutes to transcribe and edit, so this waits up to 40
      // minutes. The job keeps running on the server either way.
      final statusUri = Uri.parse('${AiBackendConstants.baseUrl}/api/v1/repurpose/$jobId');
      const pollInterval = Duration(seconds: 4);
      const maxAttempts = 600;

      Map<String, dynamic>? finalResult;
      // A dropped request here (weak signal, a brief network blip) is not
      // the same as the job failing — the 40 coins are already spent and
      // the backend may still be rendering, or already done. Losing the
      // whole result to one bad request out of up to 120 would throw away
      // real, finished work over a hiccup a retry 4 seconds later would
      // have sailed through. Only a real HTTP response (job failed, not
      // found, not yours) ends the job — a network-level exception just
      // counts against a small retry budget instead.
      var consecutiveNetworkFailures = 0;
      const maxConsecutiveNetworkFailures = 5;
      for (var attempt = 0; attempt < maxAttempts; attempt++) {
        await Future.delayed(pollInterval);
        if (!mounted) return;

        http.Response statusResponse;
        try {
          statusResponse = await http.get(
            statusUri,
            headers: {if (token != null) 'Authorization': 'Bearer $token'},
          );
        } catch (_) {
          consecutiveNetworkFailures++;
          if (consecutiveNetworkFailures >= maxConsecutiveNetworkFailures) {
            throw Exception('Lost connection while checking on your clip.');
          }
          continue;
        }
        consecutiveNetworkFailures = 0;

        if (statusResponse.statusCode != 200) {
          final body = jsonDecode(statusResponse.body);
          throw Exception(body['detail'] ?? 'Server returned ${statusResponse.statusCode}');
        }

        final statusBody = jsonDecode(statusResponse.body);
        final status = statusBody['status'] as String?;
        if (mounted) {
          setState(() {
            _serverMessage = statusBody['message'] as String?;
            _serverProgress = (statusBody['progress'] as num?)?.toDouble();
          });
        }
        if (status == 'done') {
          finalResult = statusBody['result'] as Map<String, dynamic>?;
          break;
        }
        if (status == 'failed') {
          final d = statusBody['error_detail']?.toString();
          if (mounted && d != null && d.isNotEmpty) setState(() => _errorDetail = d);
          throw Exception(statusBody['error'] ?? 'Processing failed');
        }
        // status == 'processing' — keep polling.
      }

      if (finalResult == null) {
        throw Exception(
          "Still processing after 40 minutes. Your clips are still being made on the server; "
          "if processing fails, your coins are refunded automatically.",
        );
      }

      setState(() {
        _result = finalResult;
        _selectedClipIndex = 0;
      });
    } on InsufficientCoinsException catch (e) {
      if (mounted) showInsufficientCoinsSheet(context, e);
    } catch (e) {
      setState(() => _error = 'Processing failed: ${friendlyErrorMessage(e)}');
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _isProcessing = false;
        });
        // A finished run uses the free video; a failed one gives it back.
        _refreshFreeTrial();
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
      setState(() => _error = 'Could not post: ${friendlyErrorMessage(e)}');
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  Map<String, dynamic> get _packaging =>
      Map<String, dynamic>.from((_selectedClip?['packaging'] as Map?) ?? const {});
  Map<String, dynamic> get _edits =>
      Map<String, dynamic>.from(((_version?['edits'] ?? _selectedClip?['edits']) as Map?) ?? const {});
  Map<String, dynamic> get _quality =>
      Map<String, dynamic>.from(((_version?['quality'] ?? _selectedClip?['quality']) as Map?) ?? const {});
  Map<String, dynamic> get _scores => Map<String, dynamic>.from((_selectedClip?['scores'] as Map?) ?? const {});
  Map<String, dynamic> get _retention => Map<String, dynamic>.from((_selectedClip?['retention'] as Map?) ?? const {});
  List<String> get _clipPlatforms =>
      ((_selectedClip?['platforms'] as List<dynamic>?) ?? const []).map((e) => '$e').toList();

  String get _postText {
    final pk = Map<String, dynamic>.from(((_packaging['platforms'] as Map?)?[_platform] as Map?) ?? const {});
    if (pk.isNotEmpty) {
      final tags = ((pk['hashtags'] as List?) ?? const []).map((t) => '#$t').join(' ');
      return [pk['title'] ?? '', pk['caption'] ?? pk['description'] ?? '', tags]
          .map((e) => '$e'.trim())
          .where((e) => e.isNotEmpty)
          .join('\n\n');
    }
    final hashtags = _clipHashtags.map((t) => '#$t').join(' ');
    final title = (_selectedClip?['highlight']?['suggested_title'] as String?)?.trim() ?? '';
    return [
      _clipCaption.isNotEmpty ? _clipCaption : title,
      if (hashtags.isNotEmpty) hashtags,
    ].where((s) => s.isNotEmpty).join('\n\n');
  }

  String? get _originalUrl => _selectedClip?['processed_video_url'] as String?;
  Map<String, dynamic>? get _version => _versions[_selectedClipIndex];
  String? get _clipVideoUrl => (_version?['url'] as String?) ?? _originalUrl;
  int? get _rank => int.tryParse(RegExp(r'clip_(\d+)\.mp4').firstMatch(_originalUrl ?? '')?.group(1) ?? '');

  Future<void> _applyEdits(Map<String, bool> toggles) async {
    final jobId = _jobId, rank = _rank;
    if (jobId == null || rank == null) return;
    setState(() => _applying = true);
    try {
      final v = await RepurposeService.clipEdits(jobId: jobId, rank: rank, toggles: toggles);
      if (!mounted) return;
      setState(() {
        if (v['version'] == 'original') {
          _versions.remove(_selectedClipIndex);
        } else {
          _versions[_selectedClipIndex] = v;
        }
      });
    } on StateError catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't make this version. Try again.")));
      }
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  /// The file to download or share: the tagged copy when the tag is on,
  /// falling back to the plain clip if the tag couldn't be added.
  Future<String?> _exportUrl() async {
    final url = _clipVideoUrl;
    if (url != null && _platform.isNotEmpty && _clipPlatforms.contains(_platform)) {
      final key = '$url|$_platform|$_addViyoTag';
      final cached = _platformUrls[key];
      if (cached != null) return cached;
      final rank = _rank;
      final jobId = _jobId;
      if (rank != null && jobId != null) {
        final v = await RepurposeService.platformClip(
            jobId: jobId, rank: rank, platform: _platform, tag: _addViyoTag, version: _version?['version'] as String?);
        final made = v?['url'] as String?;
        if (made != null) {
          _platformUrls[key] = made;
          return made;
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Couldn't make that version, so this is the standard clip.")),
          );
        }
      }
    }
    if (url == null || !_addViyoTag) return url;
    if (_version != null) return url;   // the tag is added to platform versions; a plain edited version stays as is
    final cached = _taggedUrls[url];
    if (cached != null) return cached;
    final rank = int.tryParse(RegExp(r'clip_(\d+)\.mp4').firstMatch(url)?.group(1) ?? '');
    final jobId = _jobId;
    if (rank == null || jobId == null) return url;
    final tagged = await RepurposeService.brandedClipUrl(jobId: jobId, rank: rank);
    if (tagged == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't add the Viyo tag, so this is the clip without it.")),
        );
      }
      return url;
    }
    _taggedUrls[url] = tagged;
    return tagged;
  }

  /// Opens the phone's share sheet with the clip itself, so it can go to
  /// TikTok, Instagram, YouTube, WhatsApp... whatever is installed. The
  /// caption is copied first, because most of those apps ignore shared text.
  Future<void> _shareClip() async {
    if (_clipVideoUrl == null) return;
    final text = _postText;
    setState(() => _sharing = true);
    try {
      final url = await _exportUrl();
      if (url == null) return;
      await Clipboard.setData(ClipboardData(text: text));
      final res = await http.get(Uri.parse(url));
      if (res.statusCode != 200) throw Exception('download failed (${res.statusCode})');
      final file = XFile.fromData(res.bodyBytes, name: 'viyo-clip.mp4', mimeType: 'video/mp4');
      await Share.shareXFiles([file], text: text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Caption copied — paste it when you post.')),
        );
      }
    } catch (_) {
      // No share sheet here (e.g. a desktop browser): save the file instead.
      await _downloadClip(captionAlreadyCopied: true);
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _downloadClip({bool captionAlreadyCopied = false}) async {
    if (_clipVideoUrl == null) return;
    setState(() => _sharing = true);
    final url = await _exportUrl();
    if (mounted) setState(() => _sharing = false);
    if (url == null) return;
    if (!captionAlreadyCopied) await Clipboard.setData(ClipboardData(text: _postText));
    // Supabase Storage sends the file as a download when ?download= is set.
    final sep = url.endsWith('?') ? '' : (url.contains('?') ? '&' : '?');
    final ok = await launchUrl(Uri.parse('$url${sep}download=viyo-clip.mp4'),
        mode: LaunchMode.externalApplication);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok
            ? 'Downloading the clip. Caption copied — paste it when you post.'
            : 'Could not open the download.'),
      ));
    }
  }

  String get _statusLabel {
    if (_isUploading) return 'Uploading video...';
    if (_isProcessing) {
      final message = _serverMessage ?? 'Processing';
      final progress = _serverProgress;
      return progress != null && progress > 0 ? '$message · ${(progress * 100).round()}%' : '$message...';
    }
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

  /// The backend's honest note when it found fewer clips than the video's
  /// length could hold ("Found 3 of up to 6 possible clips — ...").
  String get _selectionNote =>
      ((_result?['selection'] as Map<String, dynamic>?)?['note'] as String?)?.trim() ?? '';

  String get _hookLine =>
      (_selectedClip?['highlight']?['hook_line'] as String?)?.trim() ?? '';

  String get _overlayHook =>
      (_selectedClip?['highlight']?['overlay_hook'] as String?)?.trim() ?? '';

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
              'Upload a longer video — the AI finds its strongest standalone '
              'moments (up to 6, only as many as the video genuinely supports), '
              'each cropped to 9:16 with burned-in captions and dead air trimmed out.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 6),
            Text(
              _isFree
                  ? 'Your first video is free (up to $_freeMaxMinutes minutes). '
                      'After that it costs ${FeatureCoinCosts.repurpose} coins per video.'
                  : '${FeatureCoinCosts.repurpose} coins per video. '
                      'If no good clips come out, your coins are refunded.',
              style: TextStyle(
                  color: _isFree ? AppColors.success : AppColors.textMuted,
                  fontSize: 12,
                  fontWeight: _isFree ? FontWeight.w600 : FontWeight.normal),
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
                              // On web the path is a blob id, so use the file's own name.
                              _selectedVideo!.name.isNotEmpty
                                  ? _selectedVideo!.name
                                  : _selectedVideo!.path.split('/').last,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
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

            const Text(
              'Clip length',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (value, label, _) in _clipLengths)
                  ChoiceChip(
                    label: Text(label),
                    selected: _clipLength == value,
                    onSelected: _isBusy ? null : (_) => setState(() => _clipLength = value),
                    selectedColor: AppColors.primary.withValues(alpha: 0.22),
                    labelStyle: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _clipLength == value ? AppColors.primary : AppColors.textSecondary,
                    ),
                    side: BorderSide(
                        color: _clipLength == value ? AppColors.primary : AppColors.surfaceBorder),
                    showCheckmark: false,
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              _clipLengths.firstWhere((l) => l.$1 == _clipLength).$3 +
                  (_clipLength == 'auto' ? '' : ' A strong hook and ending come first.'),
              style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
            ),
            const SizedBox(height: 16),
            const Text(
              'How many shorts',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final n in const [0, 1, 3, 5, 8, 10])
                ChoiceChip(
                  label: Text(n == 0 ? 'Auto' : '$n'),
                  selected: _clipCount == n,
                  onSelected: _isBusy ? null : (_) => setState(() => _clipCount = n),
                  selectedColor: AppColors.primary.withValues(alpha: 0.22),
                  labelStyle: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _clipCount == n ? AppColors.primary : AppColors.textSecondary,
                  ),
                  side: BorderSide(color: _clipCount == n ? AppColors.primary : AppColors.surfaceBorder),
                  showCheckmark: false,
                ),
            ]),
            const SizedBox(height: 6),
            Text(
              _clipCount == 0
                  ? 'As many strong moments as your video holds (up to 6).'
                  : 'Up to $_clipCount. You get fewer if your video doesn\'t have that many strong moments.',
              style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
            ),
            const SizedBox(height: 16),

            // Optional — only matters for a silent video or one with
            // just music/ambient sound, where there's no speech for the
            // AI to find highlights in. Any video with real speech in it
            // ignores this completely, so it stays out of the way rather
            // than gating the flow.
            const Text(
              'No dialogue, or just music? (optional)',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _promptController,
              enabled: !_isBusy,
              minLines: 2,
              maxLines: 4,
              maxLength: 500,
              decoration: const InputDecoration(
                hintText: "Describe what you want the clip to look like, e.g. "
                    "\"a slow-motion sunset walk on the beach\"",
                hintStyle: TextStyle(fontSize: 12.5),
              ),
              style: const TextStyle(fontSize: 13),
            ),

            const SizedBox(height: 4),

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
                          child: _isFree
                              ? const Text('Free',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white))
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.monetization_on, size: 13, color: Colors.white),
                                    const SizedBox(width: 3),
                                    Text(
                                      '${FeatureCoinCosts.repurpose}',
                                      style: const TextStyle(
                                          fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white),
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
              if (_errorDetail != null) ...[
                const SizedBox(height: 8),
                SelectableText(
                  'Details: ${_errorDetail!.length > 1800 ? _errorDetail!.substring(0, 1800) : _errorDetail!}',
                  style: const TextStyle(color: Colors.white38, fontSize: 10),
                ),
              ],
            ],

            if (_feedback != null) ...[
              const SizedBox(height: 24),
              _VideoFeedbackCard(feedback: _feedback!),
            ],

            if (_clips.isNotEmpty) ...[
              const SizedBox(height: 24),
              if (_selectionNote.isNotEmpty) ...[
                Text(
                  _selectionNote,
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 10),
              ],
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
                      // Clips written from a description (no speech) have
                      // nothing measured behind them, so no score is shown.
                      final scored = clip['highlight']?['category'] != 'prompt';
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
                                    if (scored) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        'Score $score',
                                        style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
                                      ),
                                    ],
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
                    if (_clipVideoUrl != null) ...[
                      ClipPreviewPlayer(
                        key: ValueKey(_clipVideoUrl),
                        url: _clipVideoUrl!,
                        thumbnailUrl: _selectedClip?['thumbnail_url'] as String?,
                      ),
                      const SizedBox(height: 14),
                    ],
                    Text(
                      _selectedClip?['highlight']?['suggested_title'] ?? 'Clip ready',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _selectedClip?['highlight']?['reason'] ?? '',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                    if (_overlayHook.isNotEmpty || _hookLine.isNotEmpty) ...[
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
                                  _overlayHook.isNotEmpty ? 'ON-SCREEN HOOK' : 'OPENING LINE',
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
                              '"${_overlayHook.isNotEmpty ? _overlayHook : _hookLine}"',
                              style: const TextStyle(
                                fontSize: 13,
                                height: 1.35,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _overlayHook.isNotEmpty
                                  ? 'Shown across the top for the first seconds, in the speaker\'s own words.'
                                  : 'The first words viewers hear.',
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
                    if (_packaging.isNotEmpty) _PackagingCard(packaging: _packaging, onCopy: _copy),
                    if (_scores['source'] == 'decisions') _ScoresCard(scores: _scores),
                    if (_quality.isNotEmpty) _QualityCard(quality: _quality),
                    if (_edits.isNotEmpty) _EditsCard(edits: _edits),
                    if (_edits['editable'] == true || (_selectedClip?['edits'] as Map?)?['editable'] == true)
                      _EditChoices(
                        key: ValueKey('choices-$_selectedClipIndex-${_version?['version']}'),
                        edits: Map<String, dynamic>.from((_selectedClip?['edits'] as Map?) ?? const {}),
                        current: Map<String, dynamic>.from((_edits['toggles'] as Map?) ?? const {}),
                        busy: _applying,
                        onApply: _applyEdits,
                      ),
                    if (_version != null)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text('Your edited version is shown. Posting to your Viyo feed uses the original clip; '
                            'download or share to use this version.',
                            style: TextStyle(fontSize: 10.5, color: AppColors.textMuted)),
                      ),
                    if (((_retention['suggestions'] as List?) ?? const []).isNotEmpty)
                      _RetentionCard(retention: _retention),
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
                    const SizedBox(height: 6),
                    if (_clipPlatforms.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      const Text('Export for',
                          style: TextStyle(fontSize: 11, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      Wrap(spacing: 6, runSpacing: 6, children: [
                        for (final e in const {'': 'Any app', 'tiktok': 'TikTok', 'shorts': 'YouTube Shorts', 'reels': 'Reels'}.entries)
                          if (e.key.isEmpty || _clipPlatforms.contains(e.key))
                            ChoiceChip(
                              label: Text(e.value, style: const TextStyle(fontSize: 12)),
                              selected: _platform == e.key,
                              onSelected: _sharing ? null : (_) => setState(() => _platform = e.key),
                            ),
                      ]),
                      const SizedBox(height: 4),
                      Text(
                        _platform.isEmpty
                            ? 'Captions placed clear of every app\'s buttons.'
                            : 'Captions placed for this app, and its own title, caption and hashtags are copied.',
                        style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted),
                      ),
                    ],
                    SwitchListTile(
                      value: _addViyoTag,
                      onChanged: _sharing ? null : (v) => setState(() => _addViyoTag = v),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      activeColor: AppColors.primary,
                      title: const Text('Add "Made with Viyo" tag', style: TextStyle(fontSize: 13.5)),
                      subtitle: const Text(
                        'A small tag on downloads and shares, so viewers can find Viyo. '
                        'Clips you post on Viyo never have it.',
                        style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _sharing || _clipVideoUrl == null ? null : _shareClip,
                            icon: const Icon(Icons.ios_share, size: 16),
                            label: Text(_sharing ? 'Preparing...' : 'Share to other apps'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _sharing || _clipVideoUrl == null ? null : () => _downloadClip(),
                            icon: const Icon(Icons.download_rounded, size: 16),
                            label: const Text('Download'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'TikTok, Instagram, YouTube, WhatsApp — the caption is copied for you.',
                      style: TextStyle(fontSize: 10.5, color: AppColors.textMuted),
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


String _clock(num seconds) {
  final s = seconds.round();
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

/// What the AI editor did to this clip, in plain words.
class _EditsCard extends StatelessWidget {
  final Map<String, dynamic> edits;
  const _EditsCard({required this.edits});

  @override
  Widget build(BuildContext context) {
    final parts = ((edits['parts'] as List?) ?? const []).whereType<List>().toList();
    final repeats = ((edits['repeats_removed'] as List?) ?? const []).length;
    final pauses = (edits['pauses_tightened'] as num?)?.toInt() ?? 0;
    final cold = edits['cold_open'] as Map?;
    final zoom = (edits['zoom_cuts'] as num?)?.toInt() ?? 0;
    final lines = <(IconData, String)>[
      if (cold != null) (Icons.flash_on_rounded, 'Opens with a preview of a line from later in the clip: "${cold['text']}"'),
      if (edits['joined'] == true && parts.length >= 2)
        (Icons.call_merge_rounded,
            'Combines ${parts.length} parts of your video: ${parts.map((p) => '${_clock(p[0] as num)}–${_clock(p[1] as num)}').join(', ')}. '
                'Viewers see "Later in the video" where they join.'
                '${(edits['join'] as Map?)?['why'] != null && '${(edits['join'] as Map)['why']}'.isNotEmpty ? ' Why: ${(edits['join'] as Map)['why']}' : ''}'),
      if (((edits['retention_cuts'] as List?) ?? const []).isNotEmpty)
        (Icons.content_cut, 'Cut ${(edits['retention_cuts'] as List).length} sentence(s) that only repeated an earlier point.'),
      if ((edits['pacing_reframes'] as num? ?? 0) > 0)
        (Icons.crop_rounded, 'Reframed ${edits['pacing_reframes']} long static shot(s) at a new sentence.'),
      if ((edits['edges_moved_to_camera_cuts'] as num? ?? 0) > 0)
        (Icons.movie_filter_outlined, 'Lined up ${edits['edges_moved_to_camera_cuts']} cut(s) with camera changes.'),
      if ((edits['dropped_sentences'] as num? ?? 0) > 0)
        (Icons.content_cut, 'Cut ${edits['dropped_sentences']} off-topic sentence(s) from the middle.'),
      if (edits['trimmed_ending'] == true) (Icons.last_page_rounded, 'Ends on the payoff, not the sign-off.'),
      if (pauses > 0) (Icons.timer_outlined, 'Shortened $pauses long pause(s) (${edits['pause_seconds_removed']}s).'),
      if (repeats > 0) (Icons.replay_rounded, 'Removed $repeats false start(s), like "I— I think".'),
      if (zoom > 0) (Icons.zoom_in_rounded, 'A gentle zoom on $zoom cut(s), so jumps look intentional.'),
    ];
    if (lines.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('WHAT THE EDITOR DID',
            style: TextStyle(fontSize: 9.5, letterSpacing: 0.8, color: AppColors.textMuted, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        for (final (icon, text) in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icon, size: 14, color: AppColors.primary),
              const SizedBox(width: 7),
              Expanded(child: Text(text, style: const TextStyle(fontSize: 12, height: 1.35))),
            ]),
          ),
      ]),
    );
  }
}

/// The checks the clip went through before it was delivered. "Not checked" is never shown as passed.
class _QualityCard extends StatelessWidget {
  final Map<String, dynamic> quality;
  const _QualityCard({required this.quality});

  @override
  Widget build(BuildContext context) {
    final items = ((quality['items'] as List?) ?? const []).whereType<Map>().toList();
    if (items.isEmpty) return const SizedBox.shrink();
    final passed = items.where((i) => i['status'] == 'passed').length;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: EdgeInsets.zero,
          title: Text('Quality checks: $passed of ${items.length} passed',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          children: [
            for (final i in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(
                    switch (i['status']) {
                      'passed' => Icons.check_circle_rounded,
                      'failed' => Icons.cancel_rounded,
                      'warning' => Icons.error_outline_rounded,
                      _ => Icons.help_outline_rounded,
                    },
                    size: 15,
                    color: switch (i['status']) {
                      'passed' => AppColors.success,
                      'failed' => AppColors.danger,
                      'warning' => AppColors.coin,
                      _ => AppColors.textMuted,
                    },
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      '${i['label']}${i['status'] == 'unchecked' ? ' — not checked' : ''}'
                      '${'${i['note'] ?? ''}'.isNotEmpty ? '. ${i['note']}' : ''}',
                      style: const TextStyle(fontSize: 12, height: 1.35),
                    ),
                  ),
                ]),
              ),
          ],
        ),
      ),
    );
  }
}

/// Title and hook options and thumbnail ideas, each checked against what the speaker actually says.
class _PackagingCard extends StatelessWidget {
  final Map<String, dynamic> packaging;
  final void Function(String label, String text) onCopy;
  const _PackagingCard({required this.packaging, required this.onCopy});

  @override
  Widget build(BuildContext context) {
    final titles = ((packaging['titles'] as List?) ?? const []).map((e) => '$e').where((e) => e.isNotEmpty).toList();
    final hooks = ((packaging['hooks'] as List?) ?? const []).map((e) => '$e').where((e) => e.isNotEmpty).toList();
    final thumbs = ((packaging['thumbnail'] as List?) ?? const []).whereType<Map>().toList();
    if (titles.isEmpty && hooks.isEmpty) return const SizedBox.shrink();
    Widget option(String label, String text) => InkWell(
          onTap: () => onCopy(label, text),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              Expanded(child: Text(text, style: const TextStyle(fontSize: 12.5, height: 1.3))),
              const Icon(Icons.copy_rounded, size: 13, color: AppColors.primary),
            ]),
          ),
        );
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('TITLE AND HOOK OPTIONS',
            style: TextStyle(fontSize: 9.5, letterSpacing: 0.8, color: AppColors.textMuted, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        for (final t in titles) option('Title', t),
        if (hooks.isNotEmpty) const Divider(height: 12),
        for (final h in hooks) option('Hook', h),
        if (thumbs.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            'Thumbnail ideas: ${thumbs.map((t) => '${t['moment']}${'${t['text'] ?? ''}'.isNotEmpty ? ' ("${t['text']}")' : ''}').join('; ')}',
            style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary, height: 1.35),
          ),
        ],
        const SizedBox(height: 4),
        const Text('Written only from what the speaker says in this clip. No promise of views.',
            style: TextStyle(fontSize: 10.5, color: AppColors.textMuted)),
      ]),
    );
  }
}


/// The creator's say over each edit: switch it off (or back on) and the clip is made again from the original.
class _EditChoices extends StatefulWidget {
  final Map<String, dynamic> edits;
  final Map<String, dynamic> current;
  final bool busy;
  final Future<void> Function(Map<String, bool>) onApply;
  const _EditChoices({super.key, required this.edits, required this.current, required this.busy, required this.onApply});

  @override
  State<_EditChoices> createState() => _EditChoicesState();
}

class _EditChoicesState extends State<_EditChoices> {
  late final Map<String, bool> _on = {
    for (final k in const ['join', 'cold_open', 'retention_cuts', 'tighten', 'zoom']) k: widget.current[k] != false,
  };

  @override
  Widget build(BuildContext context) {
    final e = widget.edits;
    final options = <(String, String)>[
      if (e['can_unjoin'] == true) ('join', 'Include the part from later in the video'),
      if (e['can_cold_open'] == true) ('cold_open', 'Open with the preview line'),
      if (((e['retention_cuts'] as List?) ?? const []).isNotEmpty) ('retention_cuts', 'Cut repeated points'),
      ('tighten', 'Shorten pauses and false starts'),
      ('zoom', 'Zooms and reframes'),
    ];
    final changed = options.any((o) => _on[o.$1] != (widget.current[o.$1] != false));
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: EdgeInsets.zero,
          title: const Text('Change the edits', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          subtitle: const Text('Switch any change off and the clip is made again from your original video.',
              style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
          children: [
            for (final (key, label) in options)
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: _on[key]!,
                onChanged: widget.busy ? null : (v) => setState(() => _on[key] = v),
                title: Text(label, style: const TextStyle(fontSize: 13)),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: widget.busy || !changed ? null : () => widget.onApply(Map.of(_on)),
                child: Text(widget.busy ? 'Making it… (about a minute)' : 'Apply'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Where viewers may lose interest, measured from the clip's own words and timing.
class _RetentionCard extends StatelessWidget {
  final Map<String, dynamic> retention;
  const _RetentionCard({required this.retention});

  @override
  Widget build(BuildContext context) {
    final tips = ((retention['suggestions'] as List?) ?? const []).whereType<Map>().toList();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('WHERE VIEWERS MAY DROP OFF',
            style: TextStyle(fontSize: 9.5, letterSpacing: 0.8, color: AppColors.textMuted, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        for (final t in tips)
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.trending_down_rounded, size: 14, color: AppColors.coin),
              const SizedBox(width: 7),
              Expanded(child: Text('${t['text']}', style: const TextStyle(fontSize: 12, height: 1.35))),
            ]),
          ),
        const Text('Suggestions only: changing these would change what is said.',
            style: TextStyle(fontSize: 10.5, color: AppColors.textMuted)),
      ]),
    );
  }
}


/// How the AI judged this clip (OpenAI Decisions): each criterion's level and why. A judgement, not a view count.
class _ScoresCard extends StatelessWidget {
  final Map<String, dynamic> scores;
  const _ScoresCard({required this.scores});

  static const _names = {
    'hook': 'Hook',
    'standalone': 'Makes sense alone',
    'story': 'Story value',
    'suitable': 'Works as a short',
    'ending': 'Ending',
    'visual': 'Picture',
  };

  @override
  Widget build(BuildContext context) {
    final ex = Map<String, dynamic>.from((scores['explanations'] as Map?) ?? const {});
    if (ex.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: EdgeInsets.zero,
          title: Text('Why this clip${scores['composite'] != null ? ' · AI score ${scores['composite']}/100' : ''}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          children: [
            for (final k in _names.keys)
              if (ex[k] != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(
                        width: 120,
                        child: Text(_names[k]!,
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                    Expanded(child: Text('${ex[k]}', style: const TextStyle(fontSize: 12, height: 1.35))),
                  ]),
                ),
            if (scores['needs_second_look'] == true)
              const Text('The AI was unsure about part of this clip, so a second check was run.',
                  style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
            const Text('An AI judgement of the clip, not a prediction of views.',
                style: TextStyle(fontSize: 10.5, color: AppColors.textMuted)),
          ],
        ),
      ),
    );
  }
}
