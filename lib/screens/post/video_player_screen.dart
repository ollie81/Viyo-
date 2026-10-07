import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../../models/post.dart';
import '../../services/bunny_stream_service.dart';
import '../../services/interstitial_ad_service.dart';
import '../../services/post_service.dart';
import '../../services/supabase_service.dart';
import '../../services/watch_progress_service.dart';
import '../../theme/app_theme.dart';
import 'post_detail_screen.dart';
import '../profile/profile_screen.dart';

/// Standard single-video player for long-form/landscape content (see
/// Post.isLongForm) — everything the TikTok-style swipe feed
/// (video_feed_screen.dart) isn't meant for: a real seek bar and
/// duration the viewer can actually scrub through at will, resuming
/// mid-watch instead of always starting over, and no swipe-to-a-
/// random-next-post, since "the next thing" for a 30-minute upload
/// shouldn't be a stranger's 15-second clip.
///
/// Reuses the same proven pieces video_feed_screen.dart's _VideoPage
/// already has — the resolution self-heal retry, Bunny status
/// polling, WatchProgressService resume/save — rather than
/// reinventing them; this screen only really differs in presentation
/// (true native aspect ratio instead of FittedBox cover/contain, no
/// PageView) and in adding periodic ad breaks, which only make sense
/// for a long sit-through, not a short swipeable clip.
class VideoPlayerScreen extends StatefulWidget {
  final Post post;

  const VideoPlayerScreen({super.key, required this.post});

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  VideoPlayerController? _controller;
  bool _initError = false;
  bool _retrying = false;
  bool _processingFailedOverride = false;
  bool _liked = false;
  bool _isSubscriber = true; // fail-closed — see _loadSubscriptionStatus

  Duration? _lastSavedPosition;
  static const _savePositionInterval = Duration(seconds: 3);

  // How often a non-subscriber gets paused for an interstitial during
  // a single long-form video — sparser than the swipe feed's
  // every-4-swipes cadence (InterstitialAdService itself), since this
  // is one sitting, not a fast scroll through many posts.
  static const _adBreakInterval = Duration(minutes: 6);
  Duration _positionAtLastAdBreak = Duration.zero;

  @override
  void initState() {
    super.initState();
    _liked = widget.post.likedByMe;
    InterstitialAdService.preload();
    _loadSubscriptionStatus();
    PostService.recordView(widget.post.id);
    if (!widget.post.isVideoProcessing && !widget.post.isVideoFailed) {
      _initialize();
    } else if (widget.post.isVideoProcessing && widget.post.bunnyVideoId != null) {
      _pollBunnyStatus();
    }
  }

  Future<void> _loadSubscriptionStatus() async {
    final userId = SupabaseService.currentUserId;
    if (userId == null) {
      if (mounted) setState(() => _isSubscriber = false);
      return;
    }
    try {
      final row = await SupabaseService.client
          .from('profiles')
          .select('is_subscribed')
          .eq('id', userId)
          .maybeSingle();
      if (mounted) setState(() => _isSubscriber = row != null && row['is_subscribed'] == true);
    } catch (_) {
      // Leave _isSubscriber at its fail-closed default.
    }
  }

  Future<void> _pollBunnyStatus() async {
    final videoId = widget.post.bunnyVideoId;
    if (videoId == null) return;
    try {
      final status = await BunnyStreamService.waitForReady(videoId);
      if (!mounted || status == null) return;
      await PostService.updateVideoStatus(
        widget.post.id,
        status.failed ? 'failed' : 'ready',
        mediaUrl: status.failed ? null : status.playbackUrl,
      );
      if (!mounted) return;
      if (status.failed) {
        setState(() => _processingFailedOverride = true);
      } else {
        _initialize(urlOverride: status.playbackUrl);
      }
    } catch (_) {
      // Best-effort — worst case this viewer still sees "Processing…".
    }
  }

  Future<void> _initialize({String? urlOverride}) async {
    final url = urlOverride ?? widget.post.mediaUrl;
    if (url == null || url.trim().isEmpty) {
      if (mounted) setState(() => _initError = true);
      return;
    }

    var controller = VideoPlayerController.networkUrl(Uri.parse(url));

    try {
      await controller.initialize();
    } catch (_) {
      await controller.dispose();
      // Same resolution-mismatch retry as video_feed_screen.dart's own
      // _initialize — see that file's comment for the full story.
      final videoId = widget.post.bunnyVideoId;
      if (videoId == null) {
        if (mounted) setState(() => _initError = true);
        return;
      }
      if (mounted) setState(() => _retrying = true);
      BunnyVideoStatus? status;
      try {
        status = await BunnyStreamService.getStatus(videoId);
      } catch (_) {}
      if (status == null || !status.ready || status.playbackUrl == url) {
        if (mounted) setState(() { _retrying = false; _initError = true; });
        return;
      }
      unawaited(PostService.updateVideoStatus(widget.post.id, 'ready', mediaUrl: status.playbackUrl));
      controller = VideoPlayerController.networkUrl(Uri.parse(status.playbackUrl));
      try {
        await controller.initialize();
      } catch (_) {
        await controller.dispose();
        if (mounted) setState(() { _retrying = false; _initError = true; });
        return;
      }
      if (mounted) setState(() => _retrying = false);
    }

    try {
      await controller.setLooping(false);

      final resumeAt = await WatchProgressService.getPosition(widget.post.id);
      if (resumeAt != null && resumeAt < controller.value.duration) {
        await controller.seekTo(resumeAt);
        _lastSavedPosition = resumeAt;
        _positionAtLastAdBreak = resumeAt;
      }
    } catch (_) {
      await controller.dispose();
      if (mounted) setState(() => _initError = true);
      return;
    }

    if (!mounted) {
      await controller.dispose();
      return;
    }

    controller.addListener(_videoListener);
    setState(() => _controller = controller);

    try {
      await controller.play();
    } catch (_) {
      // Browser autoplay block on web — stays loaded and paused, same
      // tap-to-play fallback as video_feed_screen.dart.
    }
  }

  void _videoListener() {
    if (!mounted) return;
    final c = _controller;
    if (c == null || !c.value.isInitialized || c.value.duration <= Duration.zero) return;

    _maybeSavePosition(c.value.position, c.value.duration);

    // Keyed off the controller's own position, not a wall-clock timer,
    // so this naturally only ever fires while actually playing and
    // never double-fires across a pause/resume.
    if (!_isSubscriber &&
        c.value.isPlaying &&
        c.value.position - _positionAtLastAdBreak >= _adBreakInterval) {
      _positionAtLastAdBreak = c.value.position;
      c.pause();
      unawaited(InterstitialAdService.showIfReady().then((shown) {
        if (shown && mounted && _controller == c) c.play();
      }));
    }

    if (!c.value.isPlaying &&
        c.value.duration - c.value.position <= const Duration(milliseconds: 200)) {
      unawaited(WatchProgressService.clearPosition(widget.post.id));
    }

    setState(() {});
  }

  void _maybeSavePosition(Duration position, Duration duration) {
    final last = _lastSavedPosition;
    if (last != null && (position - last).abs() < _savePositionInterval) return;
    _lastSavedPosition = position;
    unawaited(WatchProgressService.savePosition(widget.post, position, duration));
  }

  @override
  void dispose() {
    _controller?.removeListener(_videoListener);
    final c = _controller;
    if (c != null && c.value.isInitialized && c.value.duration > Duration.zero) {
      unawaited(WatchProgressService.savePosition(
        widget.post, c.value.position, c.value.duration,
        forceServerSync: true,
      ));
    }
    _controller?.dispose();
    super.dispose();
  }

  void _togglePlay() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (c.value.isPlaying) {
      c.pause();
    } else {
      c.play();
    }
    setState(() {});
  }

  Future<void> _toggleLike() async {
    final userId = SupabaseService.currentUserId;
    if (userId == null) return;
    final wasLiked = _liked;
    setState(() => _liked = !_liked);
    try {
      if (wasLiked) {
        await PostService.unlikePost(userId, widget.post.id);
      } else {
        await PostService.likePost(userId, widget.post.id);
      }
    } catch (_) {
      if (mounted) setState(() => _liked = wasLiked);
    }
  }

  String _time(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    final mm = h > 0 ? m.toString().padLeft(2, '0') : m.toString();
    final ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final c = _controller;
    final ready = c?.value.isInitialized == true;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          post.caption.isNotEmpty ? post.caption : '@${post.authorUsername ?? 'video'}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white, fontSize: 15),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            GestureDetector(
              onTap: _togglePlay,
              child: Container(
                width: double.infinity,
                color: Colors.black,
                child: AspectRatio(
                  // True native shape, centered and letterboxed as
                  // needed — a YouTube/Netflix-style single player,
                  // deliberately not the swipe feed's edge-to-edge
                  // FittedBox cover/contain.
                  aspectRatio: ready ? c!.value.aspectRatio : post.displayAspectRatio,
                  child: ready
                      ? Stack(
                          alignment: Alignment.center,
                          children: [
                            VideoPlayer(c!),
                            if (!c.value.isPlaying)
                              Container(
                                color: Colors.black26,
                                child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 56),
                              ),
                          ],
                        )
                      : _mediaPlaceholder(post),
                ),
              ),
            ),
            if (ready)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    Text(_time(c!.value.position), style: const TextStyle(color: Colors.white70, fontSize: 11)),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 2,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                        ),
                        child: Slider(
                          min: 0,
                          max: c.value.duration.inMilliseconds.toDouble().clamp(1, double.infinity),
                          value: c.value.position.inMilliseconds
                              .toDouble()
                              .clamp(0, c.value.duration.inMilliseconds.toDouble()),
                          activeColor: AppColors.primary,
                          inactiveColor: Colors.white30,
                          onChanged: (v) => c.seekTo(Duration(milliseconds: v.round())),
                        ),
                      ),
                    ),
                    Text(_time(c.value.duration), style: const TextStyle(color: Colors.white70, fontSize: 11)),
                    IconButton(
                      icon: Icon(c.value.volume == 0 ? Icons.volume_off : Icons.volume_up, color: Colors.white70, size: 20),
                      onPressed: () => c.setVolume(c.value.volume == 0 ? 1 : 0),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => ProfileScreen(userId: post.userId)),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundColor: AppColors.surfaceBorder,
                            backgroundImage:
                                post.authorAvatarUrl != null ? CachedNetworkImageProvider(post.authorAvatarUrl!) : null,
                            child: post.authorAvatarUrl == null
                                ? Text((post.authorDisplayName ?? '?')[0].toUpperCase())
                                : null,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '@${post.authorUsername ?? 'unknown'}',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (post.caption.trim().isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(post.caption, style: const TextStyle(color: Colors.white70, height: 1.35)),
                    ],
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        _actionButton(
                          icon: _liked ? Icons.favorite : Icons.favorite_border,
                          color: _liked ? AppColors.secondary : Colors.white70,
                          label: '${post.likeCount + (_liked == post.likedByMe ? 0 : (_liked ? 1 : -1))}',
                          onTap: _toggleLike,
                        ),
                        const SizedBox(width: 20),
                        _actionButton(
                          icon: Icons.mode_comment_outlined,
                          color: Colors.white70,
                          label: '${post.commentCount}',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => PostDetailScreen(post: post)),
                          ),
                        ),
                        const SizedBox(width: 20),
                        _actionButton(
                          icon: Icons.share_outlined,
                          color: Colors.white70,
                          label: 'Share',
                          onTap: () => Share.share(post.mediaUrl ?? post.caption),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mediaPlaceholder(Post post) {
    if (post.isVideoProcessing && !_processingFailedOverride) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppColors.primary),
            SizedBox(height: 10),
            Text('Processing video…', style: TextStyle(color: Colors.white70)),
          ],
        ),
      );
    }
    if (post.isVideoFailed || _processingFailedOverride) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: Colors.white54, size: 44),
            SizedBox(height: 8),
            Text('This video failed to process', style: TextStyle(color: Colors.white70)),
          ],
        ),
      );
    }
    if (_retrying) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (post.thumbnailUrl != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          CachedNetworkImage(
            imageUrl: post.thumbnailUrl!,
            fit: BoxFit.cover,
            memCacheWidth: 1080,
            placeholder: (_, __) => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
            errorWidget: (_, __, ___) => _initError ? _errorIcon() : const SizedBox.shrink(),
          ),
          if (!_initError) const Center(child: CircularProgressIndicator(color: AppColors.primary)),
        ],
      );
    }
    return _initError ? _errorIcon() : const Center(child: CircularProgressIndicator(color: AppColors.primary));
  }

  Widget _errorIcon() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, color: Colors.white54, size: 44),
          SizedBox(height: 8),
          Text('Video unavailable', style: TextStyle(color: Colors.white70)),
        ],
      ),
    );
  }

  Widget _actionButton({required IconData icon, required Color color, required String label, VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: color, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}
