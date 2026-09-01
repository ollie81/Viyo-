
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../models/caption_variants.dart';
import '../../models/hook_feedback.dart';
import '../../models/post.dart';
import '../../services/ai_service.dart';
import '../../services/post_service.dart';
import '../../services/profile_service.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
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
  File? _mediaFile;
  bool _posting = false;
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

  Future<void> _pickMedia(ImageSource source, {required bool video}) async {
    final picker = ImagePicker();
    final XFile? picked = video
        ? await picker.pickVideo(source: source, maxDuration: const Duration(seconds: 30))
        : await picker.pickImage(source: source);
    if (picked != null) {
      setState(() {
        _mediaFile = File(picked.path);
        _type = video ? PostType.video : PostType.photo;
      });
    }
  }

  Future<void> _improveCaption() async {
    if (_caption.text.trim().isEmpty) return;
    setState(() => _improvingCaption = true);
    try {
      final improved = await AiService.improveCaption(_caption.text.trim());
      setState(() => _caption.text = improved);
    } catch (e) {
      setState(() => _error = 'Could not improve caption: $e');
    } finally {
      if (mounted) setState(() => _improvingCaption = false);
    }
  }

  Future<void> _checkHook() async {
    final hookText = _caption.text.trim();
    if (hookText.isEmpty) return;
    setState(() {
      _checkingHook = true;
      _hookResult = null;
    });
    try {
      final result = await AiService.analyzeHook(hookText: hookText);
      if (mounted) setState(() => _hookResult = result);
    } catch (e) {
      setState(() => _error = 'Could not check hook: $e');
    } finally {
      if (mounted) setState(() => _checkingHook = false);
    }
  }

  Future<void> _generateCaptionVariants() async {
    final draft = _caption.text.trim();
    if (draft.isEmpty) return;
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

    setState(() {
      _posting = true;
      _error = null;
    });

    final shouldProceed = await _checkVoiceBeforePosting(_caption.text.trim());
    if (!shouldProceed) {
      if (mounted) setState(() => _posting = false);
      return;
    }

    try {
      String? mediaUrl;
      String? thumbnailUrl;

      if (_mediaFile != null) {
        mediaUrl = await PostService.uploadMedia(_mediaFile!, userId);
        if (_type == PostType.video) {
          thumbnailUrl = await PostService.generateAndUploadVideoThumbnail(_mediaFile!, userId);
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
        durationSeconds: postType == PostType.video ? 30 : null,
      );

      if (!mounted) return;
      setState(() {
        _caption.clear();
        _mediaFile = null;
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
      if (mounted) setState(() => _posting = false);
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
        SnackBar(content: Text('AI Coach unavailable: $e')),
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
                _typeChip('Video (30s)', PostType.video),
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
                                  child: Image.file(_mediaFile!, fit: BoxFit.cover, width: double.infinity),
                                )
                              : const Center(
                                  child: Icon(Icons.play_circle_outline, size: 48, color: AppColors.primary),
                                ),
                        ),
                        Positioned(
                          top: 8,
                          right: 8,
                          child: IconButton(
                            icon: const Icon(Icons.close, color: Colors.white),
                            onPressed: () => setState(() => _mediaFile = null),
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
                  label: Text(
                    _checkingHook ? 'Checking...' : 'Check My Hook',
                    style: const TextStyle(color: AppColors.primary),
                  ),
                ),
                TextButton.icon(
                  onPressed: _generatingVariants ? null : _generateCaptionVariants,
                  icon: _generatingVariants
                      ? const SizedBox(
                          height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.lightbulb_outline, size: 16, color: AppColors.coin),
                  label: Text(
                    _generatingVariants ? 'Generating...' : 'Caption Ideas',
                    style: const TextStyle(color: AppColors.coin),
                  ),
                ),
                TextButton.icon(
                  onPressed: _improvingCaption ? null : _improveCaption,
                  icon: _improvingCaption
                      ? const SizedBox(
                          height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.auto_awesome, size: 16, color: AppColors.secondary),
                  label: Text(
                    _improvingCaption ? 'Improving...' : 'Improve with AI',
                    style: const TextStyle(color: AppColors.secondary),
                  ),
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
          if (type == PostType.text) _mediaFile = null;
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
