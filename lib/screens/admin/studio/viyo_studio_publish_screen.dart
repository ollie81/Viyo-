import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';
import '../../../services/studio_service.dart';
import '../../../services/web_download_stub.dart'
    if (dart.library.html) '../../../services/web_download_html.dart' as web_download;
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

  bool _uploadingMusic = false;
  String? _musicFileName;

  bool _downloading = false;

  List<String> _thumbnailCandidates = [];
  String? _selectedThumbnailUrl;
  bool _uploadingThumbnail = false;

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
        _thumbnailCandidates = result.thumbnailCandidates;
        _selectedThumbnailUrl = result.thumbnailCandidates.isNotEmpty ? result.thumbnailCandidates.first : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _assembleError = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), ''));
    } finally {
      if (mounted) setState(() => _assembling = false);
    }
  }

  /// Lets the admin pick an audio file straight from their phone (e.g.
  /// one they just downloaded from Suno) instead of needing to host it
  /// somewhere and paste a URL — uploads it and fills the URL field
  /// with the real, Studio-hosted result.
  Future<void> _pickAndUploadMusic() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.audio, withData: true);
    final picked = result?.files.single;
    if (picked == null || picked.bytes == null) return;

    setState(() => _uploadingMusic = true);
    try {
      final musicUrl = await StudioService.uploadMusic(widget.adminKey, picked.bytes!, picked.name);
      if (!mounted) return;
      setState(() {
        _musicUrlController.text = musicUrl;
        _musicFileName = picked.name;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst(RegExp(r'^Exception:\s*'), ''))),
      );
    } finally {
      if (mounted) setState(() => _uploadingMusic = false);
    }
  }

  /// Lets the admin use a cover image that isn't one of the
  /// auto-extracted candidates — uploads it and selects it.
  Future<void> _pickAndUploadThumbnail() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    final picked = result?.files.single;
    if (picked == null || picked.bytes == null) return;

    setState(() => _uploadingThumbnail = true);
    try {
      final thumbnailUrl = await StudioService.uploadThumbnail(widget.adminKey, picked.bytes!, picked.name);
      if (!mounted) return;
      setState(() {
        _thumbnailCandidates = [thumbnailUrl, ..._thumbnailCandidates];
        _selectedThumbnailUrl = thumbnailUrl;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst(RegExp(r'^Exception:\s*'), ''))),
      );
    } finally {
      if (mounted) setState(() => _uploadingThumbnail = false);
    }
  }

  /// Saves the assembled preview to the phone before publishing — e.g.
  /// to check it looks right on a real device, or to keep a copy.
  /// Downloads the bytes, then hands them off differently per platform:
  /// native writes a scratch file and opens the system share sheet
  /// (share_plus), which is what lets the admin actually choose where
  /// it lands (Files, Downloads, Photos) — Flutter has no direct "save
  /// to device storage" call of its own without a platform-specific
  /// gallery plugin. Web has no filesystem and no share sheet at all —
  /// path_provider's getTemporaryDirectory() has no web implementation,
  /// which is exactly what crashed here with a bare
  /// MissingPluginException before this split existed. web_download's
  /// Blob-URL-plus-<a download> is the actual web equivalent: it saves
  /// straight to the browser's own Downloads folder.
  Future<void> _downloadPreview() async {
    final assembled = _assembled;
    if (assembled == null) return;
    setState(() => _downloading = true);
    try {
      final res = await http.get(Uri.parse(assembled.previewVideoUrl));
      if (res.statusCode != 200) {
        throw Exception('Could not download video (${res.statusCode})');
      }
      final fileName = '${widget.seriesTitle.replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_')}'
          '_ep${widget.episodeNumber}.mp4';
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst(RegExp(r'^Exception:\s*'), ''))),
      );
    } finally {
      if (mounted) setState(() => _downloading = false);
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
        thumbnailUrl: _selectedThumbnailUrl,
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
              _thumbnailSection(),
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
            onChanged: (_) => setState(() => _musicFileName = null),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _uploadingMusic ? null : _pickAndUploadMusic,
              icon: _uploadingMusic
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.file_upload_outlined, size: 16),
              label: Text(
                _uploadingMusic
                    ? 'Uploading...'
                    : (_musicFileName != null ? 'Uploaded: $_musicFileName' : 'Upload music from phone'),
                style: const TextStyle(fontSize: 12.5),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Leave blank for no music. There\'s no bundled music library — '
            'sound effects aren\'t generated either. Upload a track you already '
            'have the rights to use, or paste a URL above.',
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
          Row(
            children: [
              const Expanded(child: Text('Preview', style: TextStyle(fontWeight: FontWeight.w700))),
              TextButton.icon(
                onPressed: _downloading ? null : _downloadPreview,
                icon: _downloading
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.download_outlined, size: 16),
                label: Text(_downloading ? 'Saving...' : 'Save to phone', style: const TextStyle(fontSize: 12.5)),
              ),
            ],
          ),
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

  Widget _thumbnailSection() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Thumbnail', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text(
            'Picked automatically from a few frames of the episode — pick the one '
            'that\'ll make someone scrolling the feed actually tap in, or upload your own.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 11.5),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 110,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                ..._thumbnailCandidates.map((url) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _thumbnailTile(url),
                    )),
                _uploadThumbnailTile(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _thumbnailTile(String url) {
    final selected = url == _selectedThumbnailUrl;
    return GestureDetector(
      onTap: () => setState(() => _selectedThumbnailUrl = url),
      child: AspectRatio(
        aspectRatio: 9 / 16,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: selected ? AppColors.primary : Colors.transparent, width: 2.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.network(url, fit: BoxFit.cover),
                if (selected)
                  Positioned(
                    right: 4,
                    top: 4,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                      child: const Icon(Icons.check, size: 12, color: Colors.white),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _uploadThumbnailTile() {
    return GestureDetector(
      onTap: _uploadingThumbnail ? null : _pickAndUploadThumbnail,
      child: AspectRatio(
        aspectRatio: 9 / 16,
        child: DottedBorderBox(
          child: _uploadingThumbnail
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
              : const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_photo_alternate_outlined, color: AppColors.textMuted, size: 22),
                      SizedBox(height: 4),
                      Text('Upload', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                    ],
                  ),
                ),
        ),
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

/// A plain dashed-border box for the "upload your own thumbnail" tile
/// — CustomPaint instead of a package since this is the only place in
/// the app that needs one.
class DottedBorderBox extends StatelessWidget {
  final Widget child;
  const DottedBorderBox({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedBorderPainter(),
      child: child,
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.textMuted.withOpacity(0.5)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(8));
    final path = Path()..addRRect(rrect);
    const dashWidth = 5.0;
    const dashSpace = 4.0;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(metric.extractPath(distance, distance + dashWidth), paint);
        distance += dashWidth + dashSpace;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
