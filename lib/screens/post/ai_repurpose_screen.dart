import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';
import '../../constants/supabase_constants.dart';
import '../../models/post.dart';
import '../../services/post_service.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'video_coach_screen.dart';

/// AI Repurposer — upload a longer video, get back up to 3 ranked
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

      await SupabaseService.client.storage
          .from(SupabaseConstants.postsBucket)
          .upload(
            storagePath,
            _selectedVideo!,
            fileOptions: FileOptions(upsert: false),
          );

      final videoUrl = SupabaseService.client.storage
          .from(SupabaseConstants.postsBucket)
          .getPublicUrl(storagePath);

      // This stable ID ties the Coach history to this exact uploaded video.
      _videoId = storagePath;

      setState(() {
        _isUploading = false;
        _isProcessing = true;
      });

      // Step 2: Send the storage URL to the Railway backend.
      // Railway now only handles a small JSON body — no timeout risk.
      final token = SupabaseService.client.auth.currentSession?.accessToken;
      final uri = Uri.parse('${AiBackendConstants.baseUrl}/api/v1/repurpose');

      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'video_url': videoUrl}),
      );

      if (response.statusCode == 200) {
        setState(() {
          _result = jsonDecode(response.body);
          _selectedClipIndex = 0;
        });
      } else {
        final body = jsonDecode(response.body);
        throw Exception(body['detail'] ?? 'Server returned ${response.statusCode}');
      }
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

    setState(() => _posting = true);
    try {
      final videoUrl = clip['processed_video_url'] as String;
      final title = clip['highlight']?['suggested_title'] as String? ?? '';

      await PostService.createPost(
        userId: userId,
        type: PostType.video,
        caption: title,
        mediaUrl: videoUrl,
        durationSeconds: 60,
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
    if (_isProcessing) return 'Processing (this can take a minute)...';
    return 'Run AI Repurpose';
  }

  bool get _isBusy => _isUploading || _isProcessing;

  List<dynamic> get _clips => (_result?['clips'] as List<dynamic>?) ?? const [];

  Map<String, dynamic>? get _selectedClip =>
      _selectedClipIndex < _clips.length ? _clips[_selectedClipIndex] as Map<String, dynamic> : null;

  double get _deadAirRemoved =>
      (_selectedClip?['dead_air_removed_seconds'] as num?)?.toDouble() ?? 0.0;

  String? get _quoteCardUrl => _selectedClip?['quote_card_url'] as String?;

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
                  : const Text('Run AI Repurpose'),
            ),

            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
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
                  height: 64,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _clips.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) {
                      final clip = _clips[i] as Map<String, dynamic>;
                      final score = (clip['highlight']?['score'] as num?)?.toInt() ?? 0;
                      final selected = i == _selectedClipIndex;
                      return GestureDetector(
                        onTap: () => setState(() => _selectedClipIndex = i),
                        child: Container(
                          width: 84,
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: selected ? AppColors.primary.withOpacity(0.15) : AppColors.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: selected ? AppColors.primary : AppColors.surfaceBorder,
                            ),
                          ),
                          child: Column(
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
                    if (_deadAirRemoved > 0.3) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppColors.success.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: AppColors.success.withOpacity(0.35)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.content_cut, size: 13, color: AppColors.success),
                            const SizedBox(width: 6),
                            Text(
                              'Trimmed ${_deadAirRemoved.toStringAsFixed(1)}s of dead air',
                              style: const TextStyle(
                                color: AppColors.success,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
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
                      child: Text(_posting ? 'Posting...' : 'Post This Clip to My Feed'),
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
