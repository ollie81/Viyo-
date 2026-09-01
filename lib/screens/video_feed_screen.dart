import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../models/post.dart';
import '../services/post_service.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/viyo_glass_bottom_nav.dart';
import 'post/post_detail_screen.dart';
import 'profile/profile_screen.dart';
import 'mission_screen.dart';
import 'post/create_post_screen.dart';
import 'search_screen.dart';

/// Viyo's video feed. It intentionally keeps the main navigation visible so
/// watching a video does not trap the user in a separate player.
class VideoFeedScreen extends StatefulWidget {
  final String? initialPostId;

  const VideoFeedScreen({super.key, this.initialPostId});

  @override
  State<VideoFeedScreen> createState() => _VideoFeedScreenState();
}

class _VideoFeedScreenState extends State<VideoFeedScreen> {
  final _pageController = PageController();
  List<Post> _posts = [];
  bool _loading = true;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final posts = await PostService.getVideoFeed();
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
          SnackBar(content: Text('Could not load videos: $e')),
        );
      }
    }
  }

  Future<void> _like(Post post) async {
    final userId = SupabaseService.currentUserId;
    if (userId == null) return;

    try {
      if (post.likedByMe) {
        await PostService.unlikePost(userId, post.id);
      } else {
        await PostService.likePost(userId, post.id);
      }

      // Refresh the feed so the server's count and liked state remain the
      // source of truth.
      final posts = await PostService.getVideoFeed();
      if (!mounted) return;
      setState(() => _posts = posts);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update like: $e')),
      );
    }
  }

  void _openComments(Post post) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PostDetailScreen(post: post)),
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

  void _selectNav(int index) {
    // Home returns to the existing HomeShell instead of creating a second
    // Home screen on top of it.
    if (index == 0) {
      Navigator.of(context).pop();
      return;
    }

    final Widget screen;
    switch (index) {
      case 1:
        screen = const SearchScreen();
        break;
      case 2:
        screen = const CreatePostScreen();
        break;
      case 3:
        screen = const MissionsScreen();
        break;
      case 4:
        screen = const ProfileScreen();
        break;
      default:
        return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => screen),
    );
  }

  @override
  void dispose() {
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
                    return _VideoPage(
                      key: ValueKey(post.id),
                      post: post,
                      isActive: i == _currentIndex,
                      onLike: () => _like(post),
                      onComment: () => _openComments(post),
                      onShare: () => _share(post),
                      onOpenProfile: () => _openProfile(post),
                    );
                  },
                ),
      bottomNavigationBar: ViyoGlassBottomNav(
        currentIndex: 0,
        onTap: _selectNav,
      ),

    );
  }
}

class _VideoPage extends StatefulWidget {
  final Post post;
  final bool isActive;
  final VoidCallback? onLike;
  final VoidCallback onComment;
  final VoidCallback onShare;
  final VoidCallback onOpenProfile;

  const _VideoPage({
    super.key,
    required this.post,
    required this.isActive,
    required this.onLike,
    required this.onComment,
    required this.onShare,
    required this.onOpenProfile,
  });

  @override
  State<_VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<_VideoPage> {
  VideoPlayerController? _controller;
  bool _muted = false;
  bool _liked = false;
  bool _initError = false;

  @override
  void initState() {
    super.initState();
    _liked = widget.post.likedByMe;
    _initialize();
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
      await controller.setLooping(true);
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
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant _VideoPage oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.post.id == oldWidget.post.id &&
        widget.post.likedByMe != oldWidget.post.likedByMe) {
      _liked = widget.post.likedByMe;
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
          onTap: _togglePlay,
          onDoubleTap: _handleLike,
          child: Container(
            color: Colors.black,
            alignment: Alignment.center,
            child: ready
                ? AspectRatio(
                    aspectRatio: c!.value.aspectRatio,
                    child: VideoPlayer(c),
                  )
                : post.thumbnailUrl != null
                    ? CachedNetworkImage(
                        imageUrl: post.thumbnailUrl!,
                        fit: BoxFit.contain,
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
          bottom: 106,
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

        // Like/comment/share actions stay above the navigation bar.
        Positioned(
          right: 12,
          bottom: 108,
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                _likeAction(post),
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

        // Playback controls are kept above the navigation bar.
        if (ready)
          Positioned(
            left: 10,
            right: 10,
            bottom: 62,
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
