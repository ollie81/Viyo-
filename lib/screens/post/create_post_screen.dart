import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../models/caption_variants.dart';
import '../../models/hook_feedback.dart';
import '../../models/insufficient_coins_exception.dart';
import '../../models/post.dart';
import '../../services/ai_service.dart';
import '../../services/bunny_stream_service.dart';
import '../../services/post_service.dart';
import '../../services/profile_service.dart';
import '../../services/supabase_service.dart';
import '../../services/video_metadata_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/friendly_error.dart';
import '../../widgets/guest_gate.dart';
import '../../widgets/insufficient_coins_sheet.dart';
import '../../widgets/upload_progress_card.dart';
import '../../widgets/xfile_preview_image.dart';
import 'coach_feedback_screen.dart';
import 'ai_repurpose_screen.dart';

class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({super.key});

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  PostType _type = PostType.text;
  final _caption = TextEditingController();
  // XFile, not dart:io's File — File doesn't work on web (throws at
  // runtime), while XFile (image_picker's own cross-platform file
  // type) reads bytes and uploads identically on every platform.
  XFile? _mediaFile;
  // A locally-extracted preview frame for a picked video — same capture
  // path used at submit time (see PostService.extractVideoThumbnail),
  // just run early so the picker shows what was actually selected
  // instead of a generic play icon that can't distinguish one video
  // from another.
  XFile? _videoThumbnail;
  // True once the creator has picked their own thumbnail — stops a
  // freshly-finished auto-extraction from clobbering that choice (the
  // extraction runs in the background and can still land after a manual
  // pick if the creator is fast).
  bool _customThumbnailPicked = false;
  bool _extractingThumbnail = false;
  bool _posting = false;
  bool _uploading = false;
  double _uploadProgress = 0;
  int _uploadTotalBytes = 0;
  bool _improvingCaption = false;
  bool _checkingHook = false;
  HookFeedback? _hookResult;
  bool _generatingVariants = false;
  CaptionVariants? _captionVariants;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Clear stale results once the caption changes, so the app never
    // shows feedback/variants for text that no longer matches what's typed.
    _caption.addListener(() {
      if (_hookResult != null) setState(() => _hookResult = null);
      if (_captionVariants != null) setState(() => _captionVariants = null);
    });
  }

  // Raised from a hardcoded 60 seconds so a creator can post real
  // long-form video directly, not just short clips — the Home feed and
  // player now adapt to a video's real length/shape instead of
  // assuming every video is short and vertical (see Post.isLongForm,
  // video_player_screen.dart). Ad breaks in the long-form player (see
  // that screen) are what makes this sustainable rather than just
  // handing out 40 minutes of ad-free viewing.
  static const _maxUploadDuration = Duration(minutes: 40);

  Future<void> _pickMedia(ImageSource source, {required bool video}) async {
    final picker = ImagePicker();
    final XFile? picked = video
        ? await picker.pickVideo(source: source, maxDuration: _maxUploadDuration)
        : await picker.pickImage(source: source);
    if (picked != null) {
      setState(() {
        _mediaFile = picked;
        _type = video ? PostType.video : PostType.photo;
        _videoThumbnail = null;
        _customThumbnailPicked = false;
      });
      if (video) _loadVideoThumbnail(picked);
    }
  }

  Future<void> _loadVideoThumbnail(XFile file) async {
    setState(() => _extractingThumbnail = true);
    final thumb = await PostService.extractVideoThumbnail(file);
    // The picker could have been reopened (or cleared), or the creator
    // could have already picked their own thumbnail, while this was
    // extracting — only apply the result if neither happened.
    if (!mounted || _mediaFile != file || _customThumbnailPicked) return;
    setState(() {
      _videoThumbnail = thumb;
      _extractingThumbnail = false;
    });
  }

  /// Lets the creator override the auto-captured frame with their own
  /// image — same option the AI Short Drama upload flow already gives
  /// (see upload_ai_drama_screen.dart's _pickThumbnail), just missing
  /// here until now.
  Future<void> _pickCustomThumbnail() async {
    // maxWidth actually constrains the picked file's size — imageQuality
    // alone doesn't: it's a JPEG compression level that image_picker
    // silently ignores for a PNG source (e.g. a phone screenshot or a
    // gallery photo saved as PNG), so without this a "thumbnail" could
    // end up multi-megabyte at full camera resolution — same fix as
    // upload_ai_drama_screen.dart's _pickThumbnail.
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1080,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _videoThumbnail = picked;
      _customThumbnailPicked = true;
      _extractingThumbnail = false;
    });
  }

  Future<void> _improveCaption() async {
    if (_caption.text.trim().isEmpty) return;
    if (!await GuestGate.allow(context, action: 'use AI caption tools')) return;
    setState(() => _improvingCaption = true);
    try {
      final improved = await AiService.improveCaption(_caption.text.trim());
      setState(() => _caption.text = improved);
    } on InsufficientCoinsException catch (e) {
      if (mounted) showInsufficientCoinsSheet(context, e);
    } catch (e) {
      setState(() => _error = 'Could not improve caption: $e');
    } finally {
      if (mounted) setState(() => _improvingCaption = false);
    }
  }

  Future<void> _checkHook() async {
    final hookText = _caption.text.trim();
    if (hookText.isEmpty) return;
    if (!await GuestGate.allow(context, action: 'use AI caption tools')) return;
    setState(() {
      _checkingHook = true;
      _hookResult = null;
    });
    try {
      final result = await AiService.analyzeHook(hookText: hookText);
      if (mounted) setState(() => _hookResult = result);
    } on InsufficientCoinsException catch (e) {
      if (mounted) showInsufficientCoinsSheet(context, e);
    } catch (e) {
      setState(() => _error = 'Could not check hook: $e');
    } finally {
      if (mounted) setState(() => _checkingHook = false);
    }
  }

  Future<void> _generateCaptionVariants() async {
    final draft = _caption.text.trim();
    if (draft.isEmpty) return;
    if (!await GuestGate.allow(context, action: 'use AI caption tools')) return;
    setState(() {
      _generatingVariants = true;
      _captionVariants = null;
    });
    try {
      String niche = '';
      final userId = SupabaseService.currentUserId;
      if (userId != null) {
        final profile = await ProfileService.getProfile(userId);
        niche = profile.niche;
      }
      final result = await AiService.getCaptionVariants(draft: draft, niche: niche);
      if (mounted) setState(() => _captionVariants = result);
    } on InsufficientCoinsException catch (e) {
      if (mounted) showInsufficientCoinsSheet(context, e);
    } catch (e) {
      setState(() => _error = 'Could not generate captions: $e');
    } finally {
      if (mounted) setState(() => _generatingVariants = false);
    }
  }

  Color _hookVerdictColor(String verdict) {
    switch (verdict) {
      case 'strong':
        return AppColors.success;
      case 'weak':
        return AppColors.danger;
      default:
        return AppColors.coin;
    }
  }

  /// Runs the voice-consistency check before posting and, if it flags
  /// the draft as off-brand, lets the creator pick the suggested
  /// rewrite or post their draft as-is. Returns false when the caption
  /// was swapped for the rewrite — the creator can review it and press
  /// Post again rather than it silently going out changed.
  /// Never blocks posting on its own failure (no profile yet, rate
  /// limited, backend hiccup) — this is a nudge, not a gate.
  Future<bool> _checkVoiceBeforePosting(String caption) async {
    if (caption.isEmpty) return true;
    try {
      final result = await AiService.checkVoice(caption);
      if (!result.hasVoiceProfile || result.consistent != false) return true;
      if (!mounted) return true;

      final choice = await showDialog<String>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text("This doesn't sound quite like you"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(result.reason ?? 'This reads differently from your usual posts.'),
              if (result.suggestedRewrite != null) ...[
                const SizedBox(height: 12),
                const Text('Suggested rewrite:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                const SizedBox(height: 4),
                Text(result.suggestedRewrite!, style: const TextStyle(fontSize: 13)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop('keep'),
              child: const Text('Post as is'),
            ),
            if (result.suggestedRewrite != null)
              TextButton(
                onPressed: () => Navigator.of(context).pop('rewrite'),
                child: const Text('Use rewrite'),
              ),
          ],
        ),
      );

      if (choice == 'rewrite' && result.suggestedRewrite != null) {
        setState(() => _caption.text = result.suggestedRewrite!);
        return false;
      }
      return true;
    } catch (_) {
      return true;
    }
  }

  Future<void> _submit() async {
    final userId = SupabaseService.currentUserId;
    if (userId == null) return;
    if (_type != PostType.text && _mediaFile == null) {
      setState(() => _error = 'Please add a photo or video');
      return;
    }
    if (_type == PostType.text && _caption.text.trim().isEmpty) {
      setState(() => _error = 'Write something first');
      return;
    }
    if (!await GuestGate.allow(context, action: 'post')) return;

    setState(() {
      _posting = true;
      _error = null;
    });

    final shouldProceed = await _checkVoiceBeforePosting(_caption.text.trim());
    if (!shouldProceed) {
      if (mounted) setState(() { _posting = false; _uploading = false; });
      return;
    }

    try {
      String? mediaUrl;
      String? thumbnailUrl;
      String? videoProvider;
      String? bunnyVideoId;
      String? videoStatus;

      if (_mediaFile != null) {
        _uploadTotalBytes = await _mediaFile!.length();
        if (mounted) {
          setState(() {
            _uploading = true;
            _uploadProgress = 0;
          });
        }

        if (_type == PostType.video) {
          // Bunny Stream first (the video's bytes go straight to Bunny,
          // never through our backend) — falls back to the existing
          // Supabase Storage path only when Bunny isn't configured on
          // the backend yet (503), so old and new videos coexist with
          // no feature flag on this side. Any other Bunny failure
          // (network drop, rejected upload) surfaces as a normal post
          // failure below rather than silently downgrading to Supabase
          // after wasting the upload time.
          try {
            final creds = await BunnyStreamService.createUploadCredentials(
              _caption.text.trim().isEmpty ? 'Viyo video' : _caption.text.trim(),
            );
            await BunnyStreamService.uploadVideo(
              _mediaFile!,
              creds,
              onProgress: (p) {
                if (mounted) setState(() => _uploadProgress = p);
              },
            );
            mediaUrl = creds.playbackUrl;
            videoProvider = 'bunny';
            bunnyVideoId = creds.videoId;
            videoStatus = 'processing';
          } on BunnyNotConfiguredException {
            mediaUrl = await PostService.uploadMediaWithProgress(
              _mediaFile!,
              userId,
              onProgress: (p) {
                if (mounted) setState(() => _uploadProgress = p);
              },
            );
          }
          if (mounted) setState(() => _uploading = false);
          // Reuse the frame already extracted for the picker's preview
          // instead of decoding the video a second time — falls back to
          // extracting fresh only if that preview capture never landed.
          // Always a small JPEG to Supabase Storage regardless of which
          // provider hosts the video itself.
          thumbnailUrl = _videoThumbnail != null
              ? await PostService.uploadMediaWithProgress(_videoThumbnail!, userId)
              : await PostService.generateAndUploadVideoThumbnail(_mediaFile!, userId);
        } else {
          // Progress-reporting upload rather than the plain one, so the
          // card below can show a real percentage instead of a spinner
          // that says nothing on a large photo.
          mediaUrl = await PostService.uploadMediaWithProgress(
            _mediaFile!,
            userId,
            onProgress: (p) {
              if (mounted) setState(() => _uploadProgress = p);
            },
          );
          if (mounted) setState(() => _uploading = false);
        }
      }

      final caption = _caption.text.trim();
      final postType = _type;
      // The image the coach will actually look at: the photo itself, or
      // the extracted video frame. Null for text posts (nothing to see).
      final coachImageUrl = postType == PostType.photo ? mediaUrl : thumbnailUrl;

      final post = await PostService.createPost(
        userId: userId,
        type: postType,
        caption: caption,
        mediaUrl: mediaUrl,
        thumbnailUrl: thumbnailUrl,
        // Left null rather than a guessed/hardcoded value — a
        // Bunny-hosted video gets its real duration (and width/height)
        // from Bunny's own API via bunny_stream.py's self-heal poll
        // below; a Supabase-hosted one gets it from the
        // probeDimensions call right after this, which ffprobes the
        // video directly. Either way the real number lands within
        // moments of posting, not a guess that's wrong for anything
        // but exactly-60-second clips.
        durationSeconds: null,
        videoProvider: videoProvider,
        bunnyVideoId: bunnyVideoId,
        videoStatus: videoStatus,
      );

      // Bunny still needs a little time to finish encoding after the
      // upload itself completes — poll in the background and flip the
      // post's status once it's ready (or failed) so the feed player
      // stops showing a "processing" state. Detached from this screen's
      // lifecycle on purpose: the creator may well navigate away before
      // Bunny finishes. Bunny's own API response (read inside
      // get_bunny_video_status) also carries this video's real
      // width/height/length, so the self-heal write-back already
      // fills those in — nothing extra needed here for a Bunny-hosted
      // video.
      if (bunnyVideoId != null) {
        BunnyStreamService.waitForReady(bunnyVideoId).then((status) async {
          if (status == null) return;
          await PostService.updateVideoStatus(
            post.id,
            status.failed ? 'failed' : 'ready',
            mediaUrl: status.failed ? null : status.playbackUrl,
          );
        }).catchError((_) {});
      } else if (postType == PostType.video && mediaUrl != null) {
        // Supabase-hosted fallback (Bunny wasn't configured) — nothing
        // else ever learns this video's real shape/length, so probe it
        // directly. Fire-and-forget, same posture as the Bunny poll
        // above: never blocks or fails the post itself.
        unawaited(VideoMetadataService.probeDimensions(postId: post.id, mediaUrl: mediaUrl));
      }

      // Client-side capture (video_thumbnail on native, a <canvas>
      // capture on web) can fail or get skipped — if this post still
      // has no thumbnail at all, fall back to the same server-side
      // ffmpeg generator the series-cover backfill uses, so a post
      // never permanently has no thumbnail just because one browser's
      // local capture didn't work.
      if (postType == PostType.video && thumbnailUrl == null && mediaUrl != null) {
        unawaited(VideoMetadataService.generateThumbnail(mediaUrl: mediaUrl, postId: post.id));
      }

      if (!mounted) return;
      setState(() {
        _caption.clear();
        _mediaFile = null;
        _videoThumbnail = null;
        _customThumbnailPicked = false;
        _type = PostType.text;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Posted! Coins added to your balance 🎉')),
      );

      // Fire the AI Creator Coach in the background — don't block the
      // posting flow on it, and don't fail the whole post if the AI
      // backend is briefly unavailable.
      _requestCoachFeedback(
        userId: userId,
        postId: post.id,
        postType: postType,
        caption: caption,
        imageUrl: coachImageUrl,
      );
    } catch (e) {
      setState(() => _error = 'Failed to post. Please try again.');
    } finally {
      if (mounted) setState(() { _posting = false; _uploading = false; });
    }
  }

  Future<void> _requestCoachFeedback({
    required String userId,
    required String postId,
    required PostType postType,
    required String caption,
    String? imageUrl,
  }) async {
    try {
      final profile = await ProfileService.getProfile(userId);
      final feedback = await AiService.analyzePost(
        postType: postType.name,
        caption: caption,
        niche: profile.niche,
        imageUrl: imageUrl,
      );
      await PostService.saveAiFeedback(feedback, postId: postId, userId: userId);

      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => CoachFeedbackScreen(feedback: feedback)),
      );
    } catch (e) {
      // Posting itself still succeeds even if the coach fails — but show
      // a quiet snackbar (not a blocking dialog) so it's visible that
      // something went wrong, instead of the feature just silently never
      // appearing with no way to tell why.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('AI Coach unavailable: ${friendlyErrorMessage(e)}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: const Text('Create Post'),
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_fix_high, color: AppColors.secondary),
            tooltip: 'AI Repurposer',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AiRepurposeScreen()),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _typeChip('Text', PostType.text),
                const SizedBox(width: 8),
                _typeChip('Photo', PostType.photo),
                const SizedBox(width: 8),
                _typeChip('Video (40 min)', PostType.video),
              ],
            ),
            const SizedBox(height: 16),
            if (_type != PostType.text)
              _mediaFile == null
                  ? OutlinedButton.icon(
                      onPressed: () => _pickMedia(ImageSource.gallery, video: _type == PostType.video),
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      label: Text('Choose ${_type == PostType.video ? "video" : "photo"}'),
                    )
                  : Stack(
                      children: [
                        Container(
                          height: 240,
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: _type == PostType.photo
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(14),
                                  child: XFilePreviewImage(file: _mediaFile!, fit: BoxFit.cover, width: double.infinity),
                                )
                              : _videoThumbnail != null
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(14),
                                      child: Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          XFilePreviewImage(
                                            file: _videoThumbnail!,
                                            fit: BoxFit.cover,
                                            width: double.infinity,
                                          ),
                                          const Center(
                                            child: Icon(
                                              Icons.play_circle_fill,
                                              size: 48,
                                              color: Colors.white70,
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  : Center(
                                      child: _extractingThumbnail
                                          ? const CircularProgressIndicator(strokeWidth: 2)
                                          : const Icon(Icons.play_circle_outline, size: 48, color: AppColors.primary),
                                    ),
                        ),
                        Positioned(
                          top: 8,
                          right: 8,
                          child: IconButton(
                            icon: const Icon(Icons.close, color: Colors.white),
                            onPressed: () => setState(() {
                              _mediaFile = null;
                              _videoThumbnail = null;
                              _customThumbnailPicked = false;
                            }),
                          ),
                        ),
                        if (_type == PostType.video)
                          Positioned(
                            left: 8,
                            bottom: 8,
                            child: GestureDetector(
                              onTap: _pickCustomThumbnail,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.55),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.add_photo_alternate_outlined, size: 14, color: Colors.white),
                                    SizedBox(width: 5),
                                    Text('Change thumbnail', style: TextStyle(color: Colors.white, fontSize: 11.5)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
            const SizedBox(height: 16),
            TextField(
              controller: _caption,
              maxLines: 4,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(hintText: "What's on your mind, creator?"),
            ),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 4,
              runSpacing: 0,
              children: [
                TextButton.icon(
                  onPressed: _checkingHook ? null : _checkHook,
                  icon: _checkingHook
                      ? const SizedBox(
                          height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.bolt, size: 16, color: AppColors.primary),
                  label: _checkingHook
                      ? const Text('Checking...', style: TextStyle(color: AppColors.primary))
                      : _CoinLabel(text: 'Check My Hook', cost: FeatureCoinCosts.hookCheck, color: AppColors.primary),
                ),
                TextButton.icon(
                  onPressed: _generatingVariants ? null : _generateCaptionVariants,
                  icon: _generatingVariants
                      ? const SizedBox(
                          height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.lightbulb_outline, size: 16, color: AppColors.coin),
                  label: _generatingVariants
                      ? const Text('Generating...', style: TextStyle(color: AppColors.coin))
                      : _CoinLabel(text: 'Caption Ideas', cost: FeatureCoinCosts.captionVariants, color: AppColors.coin),
                ),
                TextButton.icon(
                  onPressed: _improvingCaption ? null : _improveCaption,
                  icon: _improvingCaption
                      ? const SizedBox(
                          height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.auto_awesome, size: 16, color: AppColors.secondary),
                  label: _improvingCaption
                      ? const Text('Improving...', style: TextStyle(color: AppColors.secondary))
                      : _CoinLabel(text: 'Improve with AI', cost: FeatureCoinCosts.improveCaption, color: AppColors.secondary),
                ),
              ],
            ),
            if (_captionVariants != null) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: AppTheme.card(borderColor: AppColors.coin.withOpacity(0.4)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _captionVariants!.personalized
                          ? 'Based on what has worked for you before:'
                          : 'A few options to try:',
                      style: const TextStyle(fontSize: 11, color: AppColors.textMuted, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    ..._captionVariants!.variants.map(
                      (variant) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: InkWell(
                          onTap: () => setState(() {
                            _caption.text = variant;
                            _captionVariants = null;
                          }),
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceBorder.withOpacity(0.5),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(variant, style: const TextStyle(fontSize: 13)),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (_hookResult != null) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: AppTheme.card(
                  borderColor: _hookVerdictColor(_hookResult!.verdict).withOpacity(0.4),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: _hookVerdictColor(_hookResult!.verdict).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            _hookResult!.verdict.toUpperCase(),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                              color: _hookVerdictColor(_hookResult!.verdict),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _hookResult!.reason,
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                    ),
                    if (_hookResult!.rewrites.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      const Text(
                        'Try instead:',
                        style: TextStyle(fontSize: 11, color: AppColors.textMuted, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      ..._hookResult!.rewrites.map(
                        (rewrite) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: InkWell(
                            onTap: () => setState(() {
                              _caption.text = rewrite;
                              _hookResult = null;
                            }),
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceBorder.withOpacity(0.5),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(rewrite, style: const TextStyle(fontSize: 13)),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 4),
              Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
            ],
            if (_uploading) ...[
              const SizedBox(height: 12),
              UploadProgressCard(
                uploading: true,
                progress: _uploadProgress,
                totalBytes: _uploadTotalBytes,
              ),
            ],
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _posting ? null : _submit,
              child: _posting
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Post'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _typeChip(String label, PostType type) {
    final selected = _type == type;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() {
          _type = type;
          if (type == PostType.text) {
            _mediaFile = null;
            _videoThumbnail = null;
            _customThumbnailPicked = false;
          }
        }),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : AppColors.surface,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: selected ? AppColors.background : AppColors.textSecondary,
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}

/// A button label showing its coin cost — same coin chip everywhere one
/// of these AI tools is offered, so the price is never a surprise.
class _CoinLabel extends StatelessWidget {
  final String text;
  final int cost;
  final Color color;
  const _CoinLabel({required this.text, required this.cost, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(text, style: TextStyle(color: color)),
        const SizedBox(width: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.monetization_on, size: 10, color: color),
              const SizedBox(width: 2),
              Text('$cost', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
            ],
          ),
        ),
      ],
    );
  }
}
