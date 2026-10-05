import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../../services/studio_service.dart';
import '../../../theme/app_theme.dart';

/// Viyo Studio, Phase 4: assemble this episode's scenes into one 9:16
/// MP4 (ffmpeg, server-side — slow zoom/pan, burned-in captions,
/// optional background music, an end card), preview it, then publish
/// it as a real episode the same way every other episode in this app
/// gets published (Bunny Stream + a `posts` row).
///
/// Reached from the Scenes screen. Assemble and Publish are
/// deliberately separate actions — assembling never touches Bunny or
/// creates a post, so the admin can re-assemble (e.g. after fixing a
/// scene) as many times as they like before committing to publish.
class ViyoStudioPublishScreen extends StatefulWidget {
  final String adminKey;
  final String seriesId;
  final String seriesTitle;
  final int episodeNumber;

  const ViyoStudioPublishScreen({
    super.key,
    required this.adminKey,
    required this.seriesId,
    required this.seriesTitle,
    required this.episodeNumber,
  });

  @override
  State<ViyoStudioPublishScreen> createState() => _ViyoStudioPublishScreenState();
}

class _ViyoStudioPublishScreenState extends State<ViyoStudioPublishScreen> {
  final _musicUrlController = TextEditingController();
  late final _captionController = TextEditingController(
    text: '${widget.seriesTitle} - Episode ${widget.episodeNumber}',
  );

  bool _assembling = false;
  String? _assembleError;
  StudioAssembleResult? _assembled;
  VideoPlayerController? _videoController;

  bool _publishing = false;
  String? _publishError;
  StudioPublishResult? _published;

  @override
  void dispose() {
    _musicUrlController.dispose();
    _captionController.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  Future<void> _assemble() async {
    setState(() {
      _assembling = true;
      _assembleError = null;
    });
    try {
      final result = await StudioService.assembleEpisode(
        widget.adminKey,
        widget.seriesId,
        widget.episodeNumber,
        musicUrl: _musicUrlController.text.trim(),
      );
      if (!mounted) return;

      await _videoController?.dispose();
      final controller = VideoPlayerController.networkUrl(Uri.parse(result.previewVideoUrl));
      await controller.initialize();
      if (!mounted) return;

      setState(() {
        _assembled = result;
        _videoController = controller;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _assembleError = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), ''));
    } finally {
      if (mounted) setState(() => _assembling = false);
    }
  }

  Future<void> _publish() async {
    final assembled = _assembled;
    if (assembled == null) return;
    setState(() {
      _publishing = true;
      _publishError = null;
    });
    try {
      final result = await StudioService.publishEpisode(
        widget.adminKey,
        widget.seriesId,
        widget.episodeNumber,
        previewVideoUrl: assembled.previewVideoUrl,
        durationSeconds: assembled.durationSeconds,
        caption: _captionController.text.trim(),
      );
      if (!mounted) return;
      setState(() => _published = result);
    } catch (e) {
      if (!mounted) return;
      setState(() => _publishError = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), ''));
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: Text('Publish · Episode ${widget.episodeNumber}', overflow: TextOverflow.ellipsis),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          if (_published != null) _publishedCard() else ...[
            _assembleSection(),
            if (_assembled != null) ...[
              const SizedBox(height: 16),
              _previewSection(),
              const SizedBox(height: 16),
              _publishSection(),
            ],
          ],
        ],
      ),
    );
  }

  Widget _assembleSection() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Assemble episode', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          TextField(
            controller: _musicUrlController,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: const InputDecoration(
              labelText: 'Background music URL (optional)',
              hintText: 'A track you already have the rights to use',
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Leave blank for no music. There\'s no bundled music library — '
            'sound effects aren\'t generated either.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 11.5),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _assembling ? null : _assemble,
              icon: _assembling
                  ? const SizedBox(
                      width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.movie_creation_outlined, size: 18),
              label: Text(_assembling
                  ? 'Assembling... this can take a minute'
                  : (_assembled == null ? 'Assemble Episode' : 'Re-assemble')),
            ),
          ),
          if (_assembleError != null) ...[
            const SizedBox(height: 10),
            Text(_assembleError!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
          ],
        ],
      ),
    );
  }

  Widget _previewSection() {
    final controller = _videoController;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Preview', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          if (controller != null && controller.value.isInitialized)
            Center(
              child: AspectRatio(
                aspectRatio: 9 / 16,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      VideoPlayer(controller),
                      GestureDetector(
                        onTap: () => setState(() {
                          controller.value.isPlaying ? controller.pause() : controller.play();
                        }),
                        child: AnimatedBuilder(
                          animation: controller,
                          builder: (_, __) => controller.value.isPlaying
                              ? const SizedBox.shrink()
                              : Container(
                                  color: Colors.black26,
                                  child: const Icon(Icons.play_arrow, size: 54, color: Colors.white),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 8),
          Text(
            'Duration: ${_assembled!.durationSeconds}s',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
          ),
        ],
      ),
    );
  }

  Widget _publishSection() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Publish to series', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          TextField(
            controller: _captionController,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: const InputDecoration(labelText: 'Caption'),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _publishing ? null : _publish,
              icon: _publishing
                  ? const SizedBox(
                      width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.publish_outlined, size: 18),
              label: Text(_publishing ? 'Publishing...' : 'Publish Episode'),
            ),
          ),
          if (_publishError != null) ...[
            const SizedBox(height: 10),
            Text(_publishError!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
          ],
        ],
      ),
    );
  }

  Widget _publishedCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppTheme.card(),
      child: const Column(
        children: [
          Icon(Icons.check_circle_outline, color: AppColors.success, size: 40),
          SizedBox(height: 12),
          Text('Episode published!', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          SizedBox(height: 8),
          Text(
            'Bunny is still processing the video — it\'ll start playing in the app once that finishes, '
            'usually within a few minutes.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
