import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../models/post.dart';
import '../../theme/app_theme.dart';

enum ViyoMediaType { photo, video }

class ViyoPostMedia {
  final String id;
  final String mediaUrl;
  final String? thumbnailUrl;
  final ViyoMediaType type;
  final String caption;
  final String creatorName;
  final String creatorUsername;
  final String? creatorAvatarUrl;
  final bool likedByMe;
  final int likeCount;
  final int commentCount;

  const ViyoPostMedia({
    required this.id,
    required this.mediaUrl,
    this.thumbnailUrl,
    required this.type,
    this.caption = '',
    required this.creatorName,
    required this.creatorUsername,
    this.creatorAvatarUrl,
    this.likedByMe = false,
    this.likeCount = 0,
    this.commentCount = 0,
  });

  factory ViyoPostMedia.fromPost(Post post) => ViyoPostMedia(
        id: post.id,
        mediaUrl: post.mediaUrl!,
        thumbnailUrl: post.thumbnailUrl,
        type: post.postType == PostType.video
            ? ViyoMediaType.video
            : ViyoMediaType.photo,
        caption: post.caption,
        creatorName: post.authorDisplayName ?? 'Creator',
        creatorUsername: post.authorUsername ?? 'creator',
        creatorAvatarUrl: post.authorAvatarUrl,
        likedByMe: post.likedByMe,
        likeCount: post.likeCount,
        commentCount: post.commentCount,
      );
}

class ViyoPostViewer extends StatefulWidget {
  final List<ViyoPostMedia> posts;
  final int initialIndex;
  final VoidCallback? onLike;
  final VoidCallback? onComment;
  final VoidCallback? onShare;
  final VoidCallback? onFollow;
  final Future<void> Function(String postId)? onLikePost;
  final Future<void> Function(String postId)? onCommentPost;
  final Future<void> Function(String postId)? onSharePost;

  const ViyoPostViewer({
    super.key,
    required this.posts,
    this.initialIndex = 0,
    this.onLike,
    this.onComment,
    this.onShare,
    this.onFollow,
    this.onLikePost,
    this.onCommentPost,
    this.onSharePost,
  });

  @override
  State<ViyoPostViewer> createState() => _ViyoPostViewerState();
}

class _ViyoPostViewerState extends State<ViyoPostViewer> {
  late final PageController _controller;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.posts.length - 1);
    _controller = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.posts.isEmpty) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: Text('No media', style: TextStyle(color: Colors.white70))),
      );
    }

    final current = widget.posts[_index];
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 8,
        title: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: AppColors.surfaceBorder,
              backgroundImage: current.creatorAvatarUrl == null
                  ? null
                  : NetworkImage(current.creatorAvatarUrl!),
              child: current.creatorAvatarUrl == null
                  ? const Icon(Icons.person, size: 18)
                  : null,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                '@${current.creatorUsername}',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            Text(
              '${_index + 1}/${widget.posts.length}',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
      ),
      body: PageView.builder(
        controller: _controller,
        scrollDirection: Axis.vertical,
        itemCount: widget.posts.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (_, i) => _CreatorMediaPage(
          key: ValueKey(widget.posts[i].id),
          post: widget.posts[i],
          onLike: widget.onLike,
          onComment: widget.onComment,
          onShare: widget.onShare,
          onFollow: widget.onFollow,
          onLikePost: widget.onLikePost,
          onCommentPost: widget.onCommentPost,
          onSharePost: widget.onSharePost,
        ),
      ),
    );
  }
}

class _CreatorMediaPage extends StatefulWidget {
  final ViyoPostMedia post;
  final VoidCallback? onLike;
  final VoidCallback? onComment;
  final VoidCallback? onShare;
  final VoidCallback? onFollow;
  final Future<void> Function(String postId)? onLikePost;
  final Future<void> Function(String postId)? onCommentPost;
  final Future<void> Function(String postId)? onSharePost;

  const _CreatorMediaPage({
    super.key,
    required this.post,
    this.onLike,
    this.onComment,
    this.onShare,
    this.onFollow,
    this.onLikePost,
    this.onCommentPost,
    this.onSharePost,
  });

  @override
  State<_CreatorMediaPage> createState() => _CreatorMediaPageState();
}

class _CreatorMediaPageState extends State<_CreatorMediaPage> {
  VideoPlayerController? _video;
  bool _liked = false;

  @override
  void initState() {
    super.initState();
    _liked = widget.post.likedByMe;
    if (widget.post.type == ViyoMediaType.video) _initVideo();
  }

  Future<void> _initVideo() async {
    final controller = VideoPlayerController.networkUrl(Uri.parse(widget.post.mediaUrl));
    try {
      await controller.initialize();
      await controller.setLooping(true);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _video = controller);
      await controller.play();
    } catch (_) {
      await controller.dispose();
    }
  }

  @override
  void dispose() {
    _video?.dispose();
    super.dispose();
  }

  void _like() {
    setState(() => _liked = !_liked);
    if (widget.onLikePost != null) {
      widget.onLikePost!(widget.post.id);
    } else {
      widget.onLike?.call();
    }
  }

  void _comment() {
    if (widget.onCommentPost != null) {
      widget.onCommentPost!(widget.post.id);
    } else {
      widget.onComment?.call();
    }
  }

  void _share() {
    if (widget.onSharePost != null) {
      widget.onSharePost!(widget.post.id);
    } else {
      widget.onShare?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    return SafeArea(
      top: false,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDoubleTap: _like,
        child: Stack(
          children: [
            Center(child: _media()),
            Positioned(
              left: 16,
              right: 16,
              bottom: 18,
              child: SafeArea(
                top: false,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            post.creatorName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 17,
                            ),
                          ),
                          if (post.caption.trim().isNotEmpty) ...[
                            const SizedBox(height: 5),
                            Text(
                              post.caption,
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white, height: 1.35),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    Column(
                      children: [
                        _Action(
                          _liked ? Icons.favorite : Icons.favorite_border_rounded,
                          _liked ? '${post.likeCount + (widget.post.likedByMe ? 0 : 1)}' : '${post.likeCount}',
                          _like,
                          active: _liked,
                        ),
                        const SizedBox(height: 14),
                        _Action(
                          Icons.chat_bubble_outline_rounded,
                          '${post.commentCount}',
                          _comment,
                        ),
                        const SizedBox(height: 14),
                        _Action(Icons.ios_share_outlined, 'Share', _share),
                        const SizedBox(height: 14),
                        _Action(Icons.person_add_alt_1_rounded, 'Follow', widget.onFollow),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (post.type == ViyoMediaType.video && _video != null)
              Positioned(
                top: 12,
                right: 12,
                child: IconButton(
                  onPressed: () {
                    final c = _video!;
                    setState(() => c.value.isPlaying ? c.pause() : c.play());
                  },
                  icon: Icon(
                    _video!.value.isPlaying ? Icons.pause_circle_outline : Icons.play_circle_outline,
                    color: Colors.white,
                    size: 30,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _media() {
    if (widget.post.type == ViyoMediaType.photo) {
      return InteractiveViewer(
        child: Image.network(
          widget.post.mediaUrl,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const Icon(
            Icons.broken_image_outlined,
            color: Colors.white54,
            size: 60,
          ),
        ),
      );
    }
    if (_video == null || !_video!.value.isInitialized) {
      return widget.post.thumbnailUrl == null
          ? const CircularProgressIndicator(color: AppColors.primary)
          : Image.network(widget.post.thumbnailUrl!, fit: BoxFit.contain);
    }
    return AspectRatio(
      aspectRatio: _video!.value.aspectRatio,
      child: VideoPlayer(_video!),
    );
  }
}

class _Action extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool active;

  const _Action(this.icon, this.label, this.onTap, {this.active = false});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(28),
      child: Column(
        children: [
          Container(
            width: 45,
            height: 45,
            decoration: BoxDecoration(
              color: active ? AppColors.secondary.withOpacity(.22) : Colors.white.withOpacity(.10),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withOpacity(.08)),
            ),
            child: Icon(icon, color: active ? AppColors.secondary : Colors.white),
          ),
          const SizedBox(height: 3),
          Text(label, style: const TextStyle(fontSize: 9, color: Colors.white)),
        ],
      ),
    );
  }
}
