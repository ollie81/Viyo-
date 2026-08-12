import 'profile/profile_screen.dart';
import 'post/post_detail_screen.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../models/post.dart';
import '../services/post_service.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';

/// Full-screen, vertically-swipeable video feed (Shorts/TikTok style).
/// Separate from FeedScreen, which stays a scrolling card list for
/// text/photo posts.
class VideoFeedScreen extends StatefulWidget {
  const VideoFeedScreen({super.key});

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
    final posts = await PostService.getVideoFeed();
    if (!mounted) return;
    setState(() {
      _posts = posts;
      _loading = false;
    });
  }

  Future<void> _like(Post post) async {
    final userId = SupabaseService.currentUserId;
    if (userId == null) return;
    await PostService.likePost(userId, post.id);
    _load();
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
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _posts.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.videocam_off_outlined, color: Colors.white54, size: 48),
                      const SizedBox(height: 12),
                      const Text('No videos yet', style: TextStyle(color: Colors.white70)),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Back'),
                      ),
                    ],
                  ),
                )
              : PageView.builder(
                  controller: _pageController,
                  scrollDirection: Axis.vertical,
                  itemCount: _posts.length,
                  onPageChanged: (i) => setState(() => _currentIndex = i),
                  itemBuilder: (ctx, i) {
                    return _VideoPage(
                      post: _posts[i],
                      isActive: i == _currentIndex,
                      onLike: () => _like(_posts[i]),
                      onBack: i == 0 ? () => Navigator.of(context).pop() : null,
                    );
                  },
                ),
    );
  }
}

class _VideoPage extends StatefulWidget {
  final Post post;
  final bool isActive;
  final VoidCallback onLike;
  final VoidCallback? onBack;

  const _VideoPage({
    required this.post,
    required this.isActive,
    required this.onLike,
    this.onBack,
  });

  @override
  State<_VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<_VideoPage> {
  VideoPlayerController? _controller;
  bool _muted = false;
  bool _initError = false;
  bool _showControls = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final url = widget.post.mediaUrl;
    if (url == null) {
      setState(() => _initError = true);
      return;
    }
    final controller = VideoPlayerController.networkUrl(Uri.parse(url));
    try {
      await controller.initialize();
      controller.setLooping(true);
      if (widget.isActive) controller.play();
      if (!mounted) {
        controller.dispose();
        return;
      }
      controller.addListener(() => setState(() {}));
      setState(() => _controller = controller);
    } catch (_) {
      if (mounted) setState(() => _initError = true);
    }
  }

  @override
  void didUpdateWidget(covariant _VideoPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_controller == null) return;
    if (widget.isActive && !oldWidget.isActive) {
      _controller!.play();
    } else if (!widget.isActive && oldWidget.isActive) {
      _controller!.pause();
    }
  }

  void _toggleMute() {
    setState(() {
      _muted = !_muted;
      _controller?.setVolume(_muted ? 0 : 1);
    });
  }

  void _togglePlayPause() {
    final c = _controller;
    if (c == null) return;
    setState(() {
      c.value.isPlaying ? c.pause() : c.play();
      _showControls = true;
    });
  }

  void _seekBy(Duration offset) {
    final c = _controller;
    if (c == null) return;
    var target = c.value.position + offset;
    if (target < Duration.zero) target = Duration.zero;
    if (target > c.value.duration) target = c.value.duration;
    c.seekTo(target);
  }

  String _fmt(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${two(s)}';
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    return Stack(
      fit: StackFit.expand,
      children: [
        // Video or fallback thumbnail/spinner
        GestureDetector(
          onTap: _togglePlayPause,
          child: Container(
            color: Colors.black,
            child: _controller != null && _controller!.value.isInitialized
                ? FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: _controller!.value.size.width,
                      height: _controller!.value.size.height,
                      child: VideoPlayer(_controller!),
                    ),
                  )
                : (_initError
                    ? const Center(
                        child: Icon(Icons.error_outline, color: Colors.white54, size: 40),
                      )
                    : (post.thumbnailUrl != null
                        ? CachedNetworkImage(
                            imageUrl: post.thumbnailUrl!,
                            fit: BoxFit.cover,
                          )
                        : const Center(
                            child: CircularProgressIndicator(color: AppColors.primary),
                          ))),
          ),
        ),

        // Back button
        SafeArea(
          child: Align(
            alignment: Alignment.topLeft,
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ),

        // Mute toggle
        SafeArea(
          child: Align(
            alignment: Alignment.topRight,
            child: IconButton(
              icon: Icon(_muted ? Icons.volume_off : Icons.volume_up, color: Colors.white),
              onPressed: _toggleMute,
            ),
          ),
        ),

        // Full video controls: rewind / play-pause / forward + seek bar
        if (_controller != null && _controller!.value.isInitialized)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 24, 12, 8),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black54],
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.replay_10, color: Colors.white, size: 30),
                        onPressed: () => _seekBy(const Duration(seconds: -10)),
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        icon: Icon(
                          _controller!.value.isPlaying ? Icons.pause_circle : Icons.play_circle,
                          color: Colors.white,
                          size: 44,
                        ),
                        onPressed: _togglePlayPause,
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        icon: const Icon(Icons.forward_10, color: Colors.white, size: 30),
                        onPressed: () => _seekBy(const Duration(seconds: 10)),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Text(
                        _fmt(_controller!.value.position),
                        style: const TextStyle(color: Colors.white, fontSize: 11),
                      ),
                      Expanded(
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 2,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                            overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                          ),
                          child: Slider(
                            min: 0,
                            max: _controller!.value.duration.inMilliseconds.toDouble().clamp(
                                  1,
                                  double.infinity,
                                ),
                            value: _controller!.value.position.inMilliseconds
                                .toDouble()
                                .clamp(0, _controller!.value.duration.inMilliseconds.toDouble()),
                            activeColor: AppColors.primary,
                            inactiveColor: Colors.white24,
                            onChanged: (v) =>
                                _controller!.seekTo(Duration(milliseconds: v.round())),
                          ),
                        ),
                      ),
                      Text(
                        _fmt(_controller!.value.duration),
                        style: const TextStyle(color: Colors.white, fontSize: 11),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

        // Right-side action column
        Positioned(
          right: 12,
          bottom: 190,
          child: Column(
            children: [
              _ActionIcon(
                icon: post.likedByMe ? Icons.favorite : Icons.favorite_border,
                color: post.likedByMe ? AppColors.secondary : Colors.white,
                label: '${post.likeCount}',
                onTap: widget.onLike,
              ),
              const SizedBox(height: 22),
              _ActionIcon(
                icon: Icons.mode_comment_outlined,
                color: Colors.white,
                label: '${post.commentCount}',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PostDetailScreen(post: post),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              const _ActionIcon(
                icon: Icons.share_outlined,
                color: Colors.white,
                label: 'Share',
                onTap: null,
              ),
            ],
          ),
        ),

        // Bottom-left caption overlay
        Positioned(
          left: 14,
          right: 90,
          bottom: 150,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ProfileScreen(userId: post.userId),
                      ),
                    ),
                    child: CircleAvatar(
                      radius: 16,
                      backgroundColor: AppColors.surfaceBorder,
                      backgroundImage: post.authorAvatarUrl != null
                          ? CachedNetworkImageProvider(post.authorAvatarUrl!)
                          : null,
                      child: post.authorAvatarUrl == null
                          ? Text((post.authorDisplayName ?? '?')[0].toUpperCase())
                          : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ProfileScreen(userId: post.userId),
                      ),
                    ),
                    child: Text(
                      '@${post.authorUsername ?? 'unknown'}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              if (post.caption.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  post.caption,
                  style: const TextStyle(color: Colors.white),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ],
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
      onTap: onTap,
      child: Column(
        children: [
          Icon(icon, color: color, size: 30),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
        ],
      ),
    );
  }
}
