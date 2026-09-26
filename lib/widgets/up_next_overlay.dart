import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../models/post.dart';
import '../theme/app_theme.dart';

/// The end-of-episode "Up Next" card — built on top of the autoplay-next
/// mechanism that already existed in video_feed_screen.dart with no UI
/// of its own (advance was instant and silent). Two distinct states:
/// a countdown when the next episode is free to watch, and an explicit
/// choice (no auto-timer) when it's locked, so a viewer is never
/// auto-dropped into a paywall without warning.
class UpNextOverlay extends StatefulWidget {
  final Post nextPost;
  final bool nextLocked;
  final VoidCallback onCancel;
  final VoidCallback onAdvance;
  final VoidCallback onBackToSeries;
  final int countdownSeconds;

  const UpNextOverlay({
    super.key,
    required this.nextPost,
    required this.nextLocked,
    required this.onCancel,
    required this.onAdvance,
    required this.onBackToSeries,
    this.countdownSeconds = 5,
  });

  @override
  State<UpNextOverlay> createState() => _UpNextOverlayState();
}

class _UpNextOverlayState extends State<UpNextOverlay> {
  Timer? _timer;
  late int _secondsLeft = widget.countdownSeconds;
  bool _fired = false;

  @override
  void initState() {
    super.initState();
    if (!widget.nextLocked) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        setState(() => _secondsLeft--);
        if (_secondsLeft <= 0) _advance();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // Both the countdown reaching zero and a manual tap can race to call
  // this — guard so onAdvance only ever fires once.
  void _advance() {
    if (_fired) return;
    _fired = true;
    _timer?.cancel();
    widget.onAdvance();
  }

  void _cancel() {
    if (_fired) return;
    _timer?.cancel();
    widget.onCancel();
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.nextPost;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {}, // swallow taps — don't let them fall through to the player underneath
      child: Container(
        color: Colors.black.withOpacity(0.72),
        alignment: Alignment.center,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'UP NEXT',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  width: 130,
                  height: 190,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      post.thumbnailUrl != null
                          ? CachedNetworkImage(
                              imageUrl: post.thumbnailUrl!,
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) => Container(color: AppColors.surfaceBorder),
                            )
                          : Container(color: AppColors.surfaceBorder),
                      if (widget.nextLocked)
                        Container(
                          color: Colors.black.withOpacity(0.45),
                          alignment: Alignment.center,
                          child: const Icon(Icons.lock_outline, color: Colors.white, size: 28),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Episode ${post.episodeNumber ?? ''}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16),
              ),
              if (post.caption.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  post.caption,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 12.5),
                ),
              ],
              const SizedBox(height: 24),
              if (widget.nextLocked) ...[
                Text(
                  'This episode is locked · ${post.seriesCoinPrice ?? 0} coins',
                  style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 12.5),
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OutlinedButton(
                      onPressed: widget.onBackToSeries,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white38),
                      ),
                      child: const Text('Back to series'),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: _advance,
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.secondary),
                      child: const Text('View episode', style: TextStyle(color: Colors.black)),
                    ),
                  ],
                ),
              ] else ...[
                Text(
                  'Playing in $_secondsLeft…',
                  style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 12.5),
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OutlinedButton(
                      onPressed: _cancel,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white38),
                      ),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: _advance,
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                      child: const Text('Watch now'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
