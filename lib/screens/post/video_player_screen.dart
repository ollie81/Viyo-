import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../../models/post.dart';
import '../../services/bunny_stream_service.dart';
import '../../services/interstitial_ad_service.dart';
import '../../services/post_service.dart';
import '../../services/supabase_service.dart';
import '../../services/video_metadata_service.dart';
import '../../services/watch_progress_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/comments_sheet.dart';
import '../../widgets/retryable_network_image.dart';
import '../profile/profile_screen.dart';

/// Standard single-video player for long-form/landscape content (see
/// Post.isLongForm) — everything the TikTok-style swipe feed
/// (video_feed_screen.dart) isn't meant for: a real seek bar and
/// duration the viewer can actually scrub through at will, resuming
/// mid-watch instead of always starting over, a fullscreen mode, and
/// no swipe-to-a-random-next-post, since "the next thing" for a
/// 30-minute upload shouldn't be a stranger's 15-second clip.
///
/// Reuses the same proven pieces video_feed_screen.dart's _VideoPage
/// already has — the resolution self-heal retry, Bunny status
/// polling, WatchProgressService resume/save, showCommentsSheet for
/// commenting without losing the video — rather than reinventing them;
/// this screen only really differs in presentation (true native aspect
/// ratio instead of FittedBox cover/contain, no PageView) and in
/// adding periodic ad breaks, which only make sense for a long
/// sit-through, not a short swipeable clip.
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
  bool _isFullscreen = false;
  int _commentCount = 0;
  // Inline, not a modal sheet — see comments_sheet.dart's own doc for
  // why: a sheet over a player that already fills most of the screen
  // still reads as "comments just covered the video". Toggling this
  // instead shrinks the video to a small fixed area (same idea as
  // YouTube's own expanded-comments view) while it keeps playing.
  bool _showComments = false;
  List<Post> _relatedVideos = [];

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
    _commentCount = widget.post.commentCount;
    InterstitialAdService.preload();
    _loadSubscriptionStatus();
    _loadRelatedVideos();
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

  /// "More videos" below the caption — so watching one long-form post
  /// doesn't dead-end: a tap on another card opens it the same way
  /// (see the routing in _buildRelatedTile below). Best-effort and
  /// never blocks the player itself on failing.
  Future<void> _loadRelatedVideos() async {
    try {
      final all = await PostService.getVideoFeed(limit: 20);
      if (!mounted) return;
      setState(() => _relatedVideos = all.where((p) => p.id != widget.post.id).toList());
    } catch (_) {}
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

      // See VideoMetadataService.ensureDimensions's own comment — this
      // is what actually backfills width/height for a post that's
      // already playing fine, which is most of them.
      VideoMetadataService.ensureDimensions(widget.post);
      VideoMetadataService.ensureThumbnail(widget.post);
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
    // Safety net: if the viewer backed out while still in fullscreen
    // (landscape-locked, immersive system UI), leaving those set would
    // wrongly affect every other screen in the app afterward.
    if (_isFullscreen) _restoreSystemChrome();
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

  void _openComments() => setState(() => _showComments = true);

  void _closeComments() => setState(() => _showComments = false);

  void _restoreSystemChrome() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  void _toggleFullscreen() {
    final enteringFullscreen = !_isFullscreen;
    setState(() => _isFullscreen = enteringFullscreen);
    if (enteringFullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      // Only forces landscape for content that's actually wide — a
      // vertical/square video stays upright in fullscreen too, same as
      // every video platform.
      final aspectRatio = _controller?.value.aspectRatio ?? widget.post.displayAspectRatio;
      if (aspectRatio > 1.0) {
        SystemChrome.setPreferredOrientations(
          [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight],
        );
      }
    } else {
      _restoreSystemChrome();
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

    if (_isFullscreen) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _toggleFullscreen();
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            child: Stack(
              alignment: Alignment.center,
              children: [
                GestureDetector(
                  onTap: _togglePlay,
                  child: Center(
                    child: ready
                        ? AspectRatio(
                            aspectRatio: c!.value.aspectRatio,
                            child: VideoPlayer(c),
                          )
                        : _mediaPlaceholder(post),
                  ),
                ),
                if (ready) _videoControlsBar(c!, compact: true),
                Positioned(
                  top: 8,
                  left: 8,
                  child: IconButton(
                    icon: const Icon(Icons.fullscreen_exit, color: Colors.white),
                    onPressed: _toggleFullscreen,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

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
            // When comments are open the video shrinks to a small fixed
            // band instead of disappearing behind a sheet — it keeps
            // playing the whole time, same as YouTube's expanded-comments
            // view. Closed, it fills all the space between the app bar
            // and the content below, same as before.
            _showComments
                ? SizedBox(height: 200, child: _videoArea(post, c, ready))
                : Expanded(child: _videoArea(post, c, ready)),
            if (ready) _videoControlsBar(c!),
            Expanded(
              child: _showComments
                  ? CommentsPanel(
                      post: post,
                      onCommentAdded: () => setState(() => _commentCount++),
                      header: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 10, 4, 4),
                        child: Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Comments',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, color: Colors.white70),
                              onPressed: _closeComments,
                            ),
                          ],
                        ),
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
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
                                  backgroundImage: post.authorAvatarUrl != null
                                      ? CachedNetworkImageProvider(post.authorAvatarUrl!)
                                      : null,
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
                                label:
                                    '${post.likeCount + (_liked == post.likedByMe ? 0 : (_liked ? 1 : -1))}',
                                onTap: _toggleLike,
                              ),
                              const SizedBox(width: 20),
                              _actionButton(
                                icon: Icons.mode_comment_outlined,
                                color: Colors.white70,
                                label: '$_commentCount',
                                onTap: _openComments,
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
                          if (_relatedVideos.isNotEmpty) ...[
                            const SizedBox(height: 22),
                            const Text(
                              'More videos',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15),
                            ),
                            const SizedBox(height: 10),
                            ..._relatedVideos.map(_buildRelatedTile),
                          ],
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// The video surface itself, pulled out so it can be either the full
  /// remaining space (comments closed) or a small fixed band (comments
  /// open) without duplicating the Stack/placeholder logic.
  Widget _videoArea(Post post, VideoPlayerController? c, bool ready) {
    return GestureDetector(
      onTap: _togglePlay,
      child: Container(
        width: double.infinity,
        color: Colors.black,
        child: Center(
          child: AspectRatio(
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
    );
  }

  /// One row per related video — thumbnail, title/caption, creator —
  /// "in one line" per the user's own description of the layout they
  /// want below a long-form video. Tapping routes the same way
  /// feed_screen.dart does: long-form non-episode content opens here
  /// again, everything else keeps the swipe feed.
  Widget _buildRelatedTile(Post related) {
    return InkWell(
      onTap: () {
        if (!related.isEpisode && related.isLongForm) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => VideoPlayerScreen(post: related)),
          );
        } else {
          Navigator.of(context).pop();
        }
      },
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 120,
                height: 68,
                child: related.thumbnailUrl != null
                    ? RetryableNetworkImage(
                        imageUrl: related.thumbnailUrl!,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Container(color: AppColors.surfaceBorder),
                      )
                    : Container(
                        color: AppColors.surfaceBorder,
                        child: const Icon(Icons.movie_outlined, color: Colors.white38),
                      ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    related.caption.trim().isNotEmpty ? related.caption : '@${related.authorUsername ?? 'video'}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '@${related.authorUsername ?? 'unknown'}',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Shared by both the normal and fullscreen layouts — position/
  /// duration labels, the seek bar, mute, and a fullscreen toggle.
  /// [compact] trims the padding for the fullscreen overlay, which sits
  /// directly over the video rather than in its own row below it.
  Widget _videoControlsBar(VideoPlayerController c, {bool compact = false}) {
    final row = Row(
      children: [
        Text(_time(c.value.position), style: const TextStyle(color: Colors.white70, fontSize: 11)),
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
              value: c.value.position.inMilliseconds.toDouble().clamp(0, c.value.duration.inMilliseconds.toDouble()),
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
        if (!compact)
          IconButton(
            icon: const Icon(Icons.fullscreen, color: Colors.white70, size: 20),
            onPressed: _toggleFullscreen,
          ),
      ],
    );
    if (!compact) {
      return Padding(padding: const EdgeInsets.symmetric(horizontal: 14), child: row);
    }
    return Positioned(
      left: 10,
      right: 10,
      bottom: 10,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.4),
          borderRadius: BorderRadius.circular(8),
        ),
        child: row,
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
          RetryableNetworkImage(
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
