import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../models/post.dart';
import '../services/post_service.dart';
import '../services/series_service.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../utils/episode_lock.dart';
import '../utils/friendly_error.dart';
import '../widgets/comments_sheet.dart';
import '../widgets/guest_gate.dart';
import 'profile/profile_screen.dart';

/// Viyo's video feed — full-screen, immersive playback (system UI
/// hidden, video filling the whole screen) matching every other
/// short-form/drama app: a back button is the only way out, the same
/// way TikTok/Reels/drama apps work. [seriesId], when set, scopes
/// playback to just that series' episodes in order instead of the
/// global video feed — so opening Episode 1 of a drama naturally swipes
/// (and auto-advances, see _VideoPage.autoAdvance) into Episode 2, 3...
/// without ever needing to back out and pick the next one manually.
class VideoFeedScreen extends StatefulWidget {
  final String? initialPostId;
  final String? seriesId;

  const VideoFeedScreen({super.key, this.initialPostId, this.seriesId});

  @override
  State<VideoFeedScreen> createState() => _VideoFeedScreenState();
}

class _VideoFeedScreenState extends State<VideoFeedScreen> {
  final _pageController = PageController();
  List<Post> _posts = [];
  bool _loading = true;
  int _currentIndex = 0;

  // One view recorded per post per time this screen is alive — a post
  // scrolled past and back into view again doesn't recount, but a
  // fresh screen (relaunching the app, reopening the feed) does. Lives
  // here rather than on _VideoPage's own state since that widget is
  // torn down and rebuilt as the PageView recycles pages.
  final Set<String> _viewedPostIds = {};

  @override
  void initState() {
    super.initState();
    // Full-bleed playback: hide the status/nav bars while this screen is
    // up, restore them on the way out — the same immersive treatment
    // every other short-form video screen uses.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _load();
  }

  Future<List<Post>> _fetchPosts() {
    final seriesId = widget.seriesId;
    return seriesId != null
        ? SeriesService.getSeriesEpisodes(seriesId)
        : PostService.getVideoFeed();
  }

  Future<void> _load() async {
    try {
      final posts = await _fetchPosts();
      if (!mounted) return;

      var index = 0;
      if (widget.initialPostId != null) {
        final found = posts.indexWhere((p) => p.id == widget.initialPostId);
        if (found >= 0) index = found;
      }

      setState(() {
        _posts = posts;
        _currentIndex = index;
        _loading = false;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_pageController.hasClients && index > 0) {
          _pageController.jumpToPage(index);
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load videos: ${friendlyErrorMessage(e)}')),
        );
      }
    }
  }

  Future<void> _like(Post post) async {
    final userId = SupabaseService.currentUserId;
    if (userId == null) return;
    if (!await GuestGate.allow(context, action: 'like posts')) return;

    try {
      if (post.likedByMe) {
        await PostService.unlikePost(userId, post.id);
      } else {
        await PostService.likePost(userId, post.id);
      }

      // Refresh the feed so the server's count and liked state remain the
      // source of truth.
      final posts = await _fetchPosts();
      if (!mounted) return;
      setState(() => _posts = posts);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update like: ${friendlyErrorMessage(e)}')),
      );
    }
  }

  void _recordView(Post post) {
    if (!_viewedPostIds.add(post.id)) return; // already counted this session
    PostService.recordView(post.id);
    // The request itself is fire-and-forget (see PostService.recordView),
    // but the count on screen shouldn't just sit there unchanged — bump
    // it locally the moment the view is actually being recorded, same
    // as the like button's own optimistic update.
    setState(() {
      _posts = _posts
          .map((p) => p.id == post.id ? p.copyWith(viewCount: p.viewCount + 1) : p)
          .toList();
    });
  }

  Future<void> _unlockEpisode(Post post) async {
    if (!await GuestGate.allow(context, action: 'unlock this episode')) return;
    try {
      await SeriesService.unlockEpisode(post.id);
      if (!mounted) return;
      setState(() {
        _posts = _posts.map((p) => p.id == post.id ? p.copyWith(unlockedByMe: true) : p).toList();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyErrorMessage(e))),
      );
    }
  }

  void _openComments(Post post) {
    // A bottom sheet, not a full navigation — the video keeps playing
    // and visible behind it, matching what commenting looks like on
    // every other short-form feed. A full-screen route here previously
    // left the video mounted and still playing underneath, invisible,
    // since the PageView itself never changed pages.
    showCommentsSheet(
      context,
      post,
      onCommentAdded: () {
        if (!mounted) return;
        setState(() {
          _posts = _posts
              .map((p) => p.id == post.id ? p.copyWith(commentCount: p.commentCount + 1) : p)
              .toList();
        });
      },
    );
  }

  Future<void> _share(Post post) async {
    await Share.share(
      post.caption.trim().isEmpty
          ? 'Check out this video on Viyo.'
          : post.caption,
    );
  }

  void _openProfile(Post post) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ProfileScreen(userId: post.userId)),
    );
  }

  /// Auto-advance to the next episode/video once the current one finishes
  /// — see _VideoPage.autoAdvance. A no-op past the last item; a locked
  /// next episode still advances into view (showing its own paywall),
  /// same as swiping to it manually would.
  void _advanceToNext(int fromIndex) {
    final next = fromIndex + 1;
    if (next >= _posts.length || !_pageController.hasClients) return;
    _pageController.animateToPage(
      next,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : _posts.isEmpty
              ? const _EmptyVideoState()
              : PageView.builder(
                  controller: _pageController,
                  scrollDirection: Axis.vertical,
                  itemCount: _posts.length,
                  onPageChanged: (i) => setState(() => _currentIndex = i),
                  itemBuilder: (ctx, i) {
                    final post = _posts[i];
                    final locked = isEpisodeLocked(post, viewerId: SupabaseService.currentUserId);
                    return _VideoPage(
                      key: ValueKey(post.id),
                      post: post,
                      isActive: i == _currentIndex,
                      isLocked: locked,
                      // Only auto-advance within a series — the global
                      // video feed keeps its existing loop-forever
                      // behavior, since there's no "next episode" to
                      // queue up outside a series context.
                      autoAdvance: widget.seriesId != null,
                      onEnded: () => _advanceToNext(i),
                      onLike: () => _like(post),
                      onComment: () => _openComments(post),
                      onShare: () => _share(post),
                      onOpenProfile: () => _openProfile(post),
                      onBecameActive: () => _recordView(post),
                      onUnlock: () => _unlockEpisode(post),
                    );
                  },
                ),
    );
  }
}

class _VideoPage extends StatefulWidget {
  final Post post;
  final bool isActive;
  final bool isLocked;
  // When true, this page doesn't loop — it plays once and calls onEnded,
  // which the parent uses to auto-advance to the next page. Only set for
  // series playback; the general video feed keeps looping.
  final bool autoAdvance;
  final VoidCallback? onEnded;
  final VoidCallback? onLike;
  final VoidCallback onComment;
  final VoidCallback onShare;
  final VoidCallback onOpenProfile;
  final VoidCallback onBecameActive;
  final Future<void> Function() onUnlock;

  const _VideoPage({
    super.key,
    required this.post,
    required this.isActive,
    required this.isLocked,
    this.autoAdvance = false,
    this.onEnded,
    required this.onLike,
    required this.onComment,
    required this.onShare,
    required this.onOpenProfile,
    required this.onBecameActive,
    required this.onUnlock,
  });

  @override
  State<_VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<_VideoPage> {
  VideoPlayerController? _controller;
  bool _ended = false;
  bool _muted = false;
  bool _liked = false;
  bool _initError = false;
  bool _unlocking = false;

  Future<void> _handleUnlock() async {
    if (_unlocking) return;
    setState(() => _unlocking = true);
    try {
      await widget.onUnlock();
    } finally {
      if (mounted) setState(() => _unlocking = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _liked = widget.post.likedByMe;
    // A locked episode never even downloads its video — there's
    // nothing to play until it's unlocked, so starting a network
    // fetch for it would just waste bandwidth on content the viewer
    // can't watch yet.
    if (!widget.isLocked) _initialize();
    if (widget.isActive) widget.onBecameActive();
  }

  Future<void> _initialize() async {
    final url = widget.post.mediaUrl;
    if (url == null || url.trim().isEmpty) {
      if (mounted) setState(() => _initError = true);
      return;
    }

    final controller = VideoPlayerController.networkUrl(Uri.parse(url));

    try {
      await controller.initialize();
      await controller.setLooping(!widget.autoAdvance);
      await controller.setVolume(_muted ? 0 : 1);

      if (!mounted) {
        await controller.dispose();
        return;
      }

      controller.addListener(_videoListener);
      setState(() => _controller = controller);

      if (widget.isActive) {
        await controller.play();
      }
    } catch (_) {
      await controller.dispose();
      if (mounted) setState(() => _initError = true);
    }
  }

  void _videoListener() {
    if (!mounted) return;
    // video_player has no explicit "completed" event — a non-looping
    // controller just pauses once it reaches the end, so that's the
    // signal to treat as "this episode is over" and fire onEnded once.
    if (widget.autoAdvance && !_ended) {
      final c = _controller;
      if (c != null && c.value.isInitialized && c.value.duration > Duration.zero) {
        final remaining = c.value.duration - c.value.position;
        if (remaining <= const Duration(milliseconds: 200)) {
          _ended = true;
          widget.onEnded?.call();
        }
      }
    }
    setState(() {});
  }

  @override
  void didUpdateWidget(covariant _VideoPage oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.post.id == oldWidget.post.id &&
        widget.post.likedByMe != oldWidget.post.likedByMe) {
      _liked = widget.post.likedByMe;
    }

    if (widget.isActive && !oldWidget.isActive) {
      widget.onBecameActive();
    }

    if (oldWidget.isLocked && !widget.isLocked && _controller == null) {
      // Just unlocked — nothing was ever downloaded while it was
      // locked, so this is the first real chance to start.
      _initialize();
    }

    final c = _controller;
    if (c == null || !c.value.isInitialized) return;

    if (widget.isActive && !oldWidget.isActive) {
      c.play();
    } else if (!widget.isActive && oldWidget.isActive) {
      c.pause();
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_videoListener);
    _controller?.dispose();
    super.dispose();
  }

  void _handleLike() {
    setState(() {
      _liked = !_liked;
    });
    widget.onLike?.call();
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

  void _toggleMute() {
    setState(() => _muted = !_muted);
    _controller?.setVolume(_muted ? 0 : 1);
  }

  String _time(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final c = _controller;
    final ready = c?.value.isInitialized == true;

    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.isLocked ? null : _togglePlay,
          onDoubleTap: widget.isLocked ? null : _handleLike,
          child: Container(
            color: Colors.black,
            alignment: Alignment.center,
            // Full-bleed, edge-to-edge playback (BoxFit.cover) instead of
            // a letterboxed AspectRatio box — matches every other
            // short-form/drama app. VideoPlayer has no fit param of its
            // own, so FittedBox + a SizedBox at the video's natural size
            // is the standard way to get cover behavior from it.
            child: widget.isLocked
                ? _lockedMedia()
                : ready
                    ? FittedBox(
                        fit: BoxFit.cover,
                        child: SizedBox(
                          width: c!.value.size.width,
                          height: c.value.size.height,
                          child: VideoPlayer(c),
                        ),
                      )
                    : post.thumbnailUrl != null
                        ? CachedNetworkImage(
                            imageUrl: post.thumbnailUrl!,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                            placeholder: (_, __) => const Center(
                              child: CircularProgressIndicator(
                                color: AppColors.primary,
                              ),
                            ),
                            errorWidget: (_, __, ___) => _videoError(),
                          )
                        : _initError
                            ? _videoError()
                            : const Center(
                                child: CircularProgressIndicator(
                                  color: AppColors.primary,
                                ),
                              ),
          ),
        ),

        if (post.isEpisode)
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: _SeriesBadge(post: post),
              ),
            ),
          ),

        SafeArea(
          child: Align(
            alignment: Alignment.topLeft,
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ),

        SafeArea(
          child: Align(
            alignment: Alignment.topRight,
            child: IconButton(
              icon: Icon(
                _muted ? Icons.volume_off : Icons.volume_up,
                color: Colors.white,
              ),
              onPressed: _toggleMute,
            ),
          ),
        ),

        // Creator and caption.
        Positioned(
          left: 14,
          right: 82,
          bottom: 36,
          child: SafeArea(
            top: false,
            child: GestureDetector(
              onTap: widget.onOpenProfile,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: AppColors.surfaceBorder,
                        backgroundImage: post.authorAvatarUrl != null
                            ? CachedNetworkImageProvider(
                                post.authorAvatarUrl!,
                              )
                            : null,
                        child: post.authorAvatarUrl == null
                            ? Text(
                                (post.authorDisplayName ?? '?')[0]
                                    .toUpperCase(),
                              )
                            : null,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          '@${post.authorUsername ?? 'unknown'}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (post.caption.trim().isNotEmpty) ...[
                    const SizedBox(height: 7),
                    Text(
                      post.caption,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        height: 1.3,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),

        // Like/comment/share actions.
        Positioned(
          right: 12,
          bottom: 38,
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                _likeAction(post),
                const SizedBox(height: 18),
                _ActionIcon(
                  icon: Icons.visibility_outlined,
                  color: Colors.white,
                  label: '${post.viewCount}',
                  onTap: null,
                ),
                const SizedBox(height: 18),
                _ActionIcon(
                  icon: Icons.mode_comment_outlined,
                  color: Colors.white,
                  label: '${post.commentCount}',
                  onTap: widget.onComment,
                ),
                const SizedBox(height: 18),
                _ActionIcon(
                  icon: Icons.share_outlined,
                  color: Colors.white,
                  label: 'Share',
                  onTap: widget.onShare,
                ),
              ],
            ),
          ),
        ),

        // Playback controls.
        if (ready)
          Positioned(
            left: 10,
            right: 10,
            bottom: 10,
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Text(
                    _time(c!.value.position),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                    ),
                  ),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 2,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 5,
                        ),
                        overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 10,
                        ),
                      ),
                      child: Slider(
                        min: 0,
                        max: c.value.duration.inMilliseconds
                            .toDouble()
                            .clamp(1, double.infinity),
                        value: c.value.position.inMilliseconds
                            .toDouble()
                            .clamp(
                              0,
                              c.value.duration.inMilliseconds.toDouble(),
                            ),
                        activeColor: AppColors.primary,
                        inactiveColor: Colors.white30,
                        onChanged: (v) => c.seekTo(
                          Duration(milliseconds: v.round()),
                        ),
                      ),
                    ),
                  ),
                  Text(
                    _time(c.value.duration),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  /// Its own widget (rather than the generic _ActionIcon) so the heart can
  /// "pop" on tap, matching the same feedback the feed's PostCard gives.
  Widget _likeAction(Post post) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onLike,
      child: Column(
        children: [
          TweenAnimationBuilder<double>(
            key: ValueKey(_liked),
            tween: Tween(begin: _liked ? 1.4 : 1.0, end: 1.0),
            duration: const Duration(milliseconds: 280),
            curve: Curves.elasticOut,
            builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
            child: Icon(
              _liked ? Icons.favorite : Icons.favorite_border,
              color: _liked ? AppColors.secondary : Colors.white,
              size: 30,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${post.likeCount + (_liked == post.likedByMe ? 0 : (_liked ? 1 : -1))}',
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _videoError() {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.error_outline,
          color: Colors.white54,
          size: 44,
        ),
        SizedBox(height: 8),
        Text(
          'Video unavailable',
          style: TextStyle(color: Colors.white70),
        ),
      ],
    );
  }

  /// A blurred thumbnail behind an unlock paywall — the episode's
  /// video was never even downloaded (see initState), so this is
  /// deliberately the thumbnail, not a frame of the real video.
  Widget _lockedMedia() {
    final post = widget.post;
    final price = post.seriesCoinPrice ?? 0;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (post.thumbnailUrl != null)
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: CachedNetworkImage(
              imageUrl: post.thumbnailUrl!,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => Container(color: Colors.black),
            ),
          )
        else
          Container(color: Colors.black),
        Container(color: Colors.black.withOpacity(0.45)),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.12),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white24),
                ),
                child: const Icon(Icons.lock_outline, color: Colors.white, size: 26),
              ),
              const SizedBox(height: 14),
              Text(
                'Episode ${post.episodeNumber ?? ''} is locked',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _handleUnlock,
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.secondary),
                icon: _unlocking
                    ? const SizedBox(
                        height: 14, width: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                      )
                    : const Icon(Icons.monetization_on, size: 16, color: Colors.black),
                label: Text(
                  _unlocking ? 'Unlocking...' : 'Unlock for $price coins',
                  style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EmptyVideoState extends StatelessWidget {
  const _EmptyVideoState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.videocam_off_outlined, color: Colors.white54, size: 28),
          ),
          const SizedBox(height: 16),
          const Text(
            'No videos yet',
            style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// The one visual marker that tells an AI Short Drama episode apart
/// from an ordinary video in the same feed — a small sparkle pill
/// naming the series and episode number.
class _SeriesBadge extends StatelessWidget {
  final Post post;
  const _SeriesBadge({required this.post});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.45),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.secondary.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.auto_awesome, size: 12, color: AppColors.secondary),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              '${post.seriesTitle ?? 'Short Drama'} · Ep ${post.episodeNumber ?? ''}',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback? onTap;

  const _ActionIcon({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        children: [
          Icon(icon, color: color, size: 30),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
