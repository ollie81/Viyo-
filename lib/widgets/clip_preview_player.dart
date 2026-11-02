import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../theme/app_theme.dart';

/// Plays a finished 9:16 clip inline so the creator can watch it before
/// posting. Tap to play/pause; it loops while previewing. Loads only when
/// first tapped, so opening the results screen doesn't download every clip.
class ClipPreviewPlayer extends StatefulWidget {
  final String url;
  final String? thumbnailUrl;

  const ClipPreviewPlayer({super.key, required this.url, this.thumbnailUrl});

  @override
  State<ClipPreviewPlayer> createState() => _ClipPreviewPlayerState();
}

class _ClipPreviewPlayerState extends State<ClipPreviewPlayer> {
  VideoPlayerController? _controller;
  bool _loading = false;
  String? _error;

  Future<void> _toggle() async {
    final c = _controller;
    if (c == null) {
      setState(() {
        _loading = true;
        _error = null;
      });
      final created = VideoPlayerController.networkUrl(Uri.parse(widget.url));
      try {
        await created.initialize();
        await created.setLooping(true);
        await created.play();
        if (!mounted) {
          await created.dispose();
          return;
        }
        created.addListener(_onTick);
        setState(() {
          _controller = created;
          _loading = false;
        });
      } catch (e) {
        await created.dispose();
        if (mounted) {
          setState(() {
            _loading = false;
            _error = 'Could not play this clip here. Use Download to watch it.';
          });
        }
      }
      return;
    }
    c.value.isPlaying ? await c.pause() : await c.play();
    if (mounted) setState(() {});
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller?.removeListener(_onTick);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    final ready = c != null && c.value.isInitialized;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 260),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: AspectRatio(
            aspectRatio: 9 / 16,
            child: GestureDetector(
              onTap: _loading ? null : _toggle,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(color: Colors.black),
                  if (ready)
                    FittedBox(
                      fit: BoxFit.contain,
                      child: SizedBox(
                        width: c.value.size.width,
                        height: c.value.size.height,
                        child: VideoPlayer(c),
                      ),
                    )
                  else if (widget.thumbnailUrl != null)
                    Image.network(
                      widget.thumbnailUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  if (_loading)
                    const Center(child: CircularProgressIndicator(strokeWidth: 2.5))
                  else if (!ready || !c.value.isPlaying)
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                        child: const Icon(Icons.play_arrow_rounded, size: 40, color: Colors.white),
                      ),
                    ),
                  if (ready)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: VideoProgressIndicator(
                        c,
                        allowScrubbing: true,
                        colors: const VideoProgressColors(playedColor: AppColors.primary),
                      ),
                    ),
                  if (_error != null)
                    Positioned(
                      left: 10,
                      right: 10,
                      bottom: 14,
                      child: Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
