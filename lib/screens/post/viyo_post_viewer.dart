import 'package:flutter/material.dart';

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
}

/// Full-screen media viewer used by creator profiles and feeds.
///
/// The actual video playback dependency can be connected in one place when
/// the project's current video-player package is known.
class ViyoPostViewer extends StatelessWidget {
  final ViyoPostMedia post;
  final VoidCallback? onLike;
  final VoidCallback? onComment;
  final VoidCallback? onShare;
  final VoidCallback? onFollow;

  const ViyoPostViewer({
    super.key,
    required this.post,
    this.onLike,
    this.onComment,
    this.onShare,
    this.onFollow,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundImage: post.creatorAvatarUrl == null
                  ? null
                  : NetworkImage(post.creatorAvatarUrl!),
              child: post.creatorAvatarUrl == null
                  ? const Icon(Icons.person, size: 18)
                  : null,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                '@${post.creatorUsername}',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
      body: Stack(
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
                : _VideoPlaceholder(
                    thumbnailUrl: post.thumbnailUrl,
                    mediaUrl: post.mediaUrl,
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
                            style: const TextStyle(height: 1.35),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Column(
                    children: [
                      _Action(Icons.favorite_border_rounded, 'Like', onLike),
                      const SizedBox(height: 14),
                      _Action(Icons.chat_bubble_outline_rounded, 'Comment',
                          onComment),
                      const SizedBox(height: 14),
                      _Action(Icons.ios_share_outlined, 'Share', onShare),
                      const SizedBox(height: 14),
                      _Action(Icons.person_add_alt_1_rounded, 'Follow',
                          onFollow),
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
            child: Icon(icon),
          ),
          const SizedBox(height: 3),
          Text(label, style: const TextStyle(fontSize: 9)),
        ],
      ),
    );
  }
}

class _VideoPlaceholder extends StatelessWidget {
  final String? thumbnailUrl;
  final String mediaUrl;

  const _VideoPlaceholder({
    required this.thumbnailUrl,
    required this.mediaUrl,
  });

  @override
  Widget build(BuildContext context) {
    // Keeps this file dependency-free. The project's existing video player
    // should replace this widget when the current player package/API is wired.
    return Stack(
      alignment: Alignment.center,
      children: [
        if (thumbnailUrl != null && thumbnailUrl!.isNotEmpty)
          Positioned.fill(
            child: Image.network(thumbnailUrl!, fit: BoxFit.contain),
          )
        else
          const Positioned.fill(
            child: ColoredBox(color: Color(0xFF10131C)),
          ),
        Container(
          width: 68,
          height: 68,
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(.55),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.play_arrow_rounded, size: 42),
        ),
      ],
    );
  }
}
