import 'package:flutter/material.dart';
import '../../models/post.dart';

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

  const ViyoPostMedia({
    required this.id,
    required this.mediaUrl,
    this.thumbnailUrl,
    required this.type,
    this.caption = '',
    required this.creatorName,
    required this.creatorUsername,
    this.creatorAvatarUrl,
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
      );
}

class ViyoPostViewer extends StatefulWidget {
  final List<ViyoPostMedia> posts;
  final int initialIndex;
  final VoidCallback? onLike;
  final VoidCallback? onComment;
  final VoidCallback? onShare;
  final VoidCallback? onFollow;

  const ViyoPostViewer({
    super.key,
    required this.posts,
    this.initialIndex = 0,
    this.onLike,
    this.onComment,
    this.onShare,
    this.onFollow,
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
        body: Center(
          child: Text(
            'No media',
            style: TextStyle(color: Colors.white70),
          ),
        ),
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
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
      body: PageView.builder(
        controller: _controller,
        scrollDirection: Axis.vertical,
        itemCount: widget.posts.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (_, i) => _page(widget.posts[i]),
      ),
    );
  }

  Widget _page(ViyoPostMedia post) {
    return SafeArea(
      top: false,
      child: Stack(
        children: [
          Center(
            child: post.type == ViyoMediaType.photo
                ? InteractiveViewer(
                    child: Image.network(
                      post.mediaUrl,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.broken_image_outlined,
                        color: Colors.white54,
                        size: 60,
                      ),
                    ),
                  )
                : Stack(
                    alignment: Alignment.center,
                    children: [
                      if (post.thumbnailUrl != null &&
                          post.thumbnailUrl!.isNotEmpty)
                        Image.network(
                          post.thumbnailUrl!,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const SizedBox(),
                        ),
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(.55),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 40,
                        ),
                      ),
                    ],
                  ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 18,
            child: SafeArea(
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
                            style: const TextStyle(
                              color: Colors.white,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Column(
                    children: [
                      _Action(
                        Icons.favorite_border_rounded,
                        'Like',
                        widget.onLike,
                      ),
                      const SizedBox(height: 14),
                      _Action(
                        Icons.chat_bubble_outline_rounded,
                        'Comment',
                        widget.onComment,
                      ),
                      const SizedBox(height: 14),
                      _Action(
                        Icons.ios_share_outlined,
                        'Share',
                        widget.onShare,
                      ),
                      const SizedBox(height: 14),
                      _Action(
                        Icons.person_add_alt_1_rounded,
                        'Follow',
                        widget.onFollow,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Action extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _Action(this.icon, this.label, this.onTap);

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
              color: Colors.white.withOpacity(.10),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withOpacity(.08)),
            ),
            child: Icon(
              icon,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: const TextStyle(
              fontSize: 9,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
