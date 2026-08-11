import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../models/post.dart';
import '../theme/app_theme.dart';
import '../screens/post/post_detail_screen.dart';

class PostCard extends StatelessWidget {
  final Post post;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback? onOpenProfile;
  final String? currentUserId;
  final VoidCallback? onDelete;

  const PostCard({
    super.key,
    required this.post,
    required this.onLike,
    required this.onComment,
    this.onOpenProfile,
    this.currentUserId,
    this.onDelete,
  });

  void _openPostDetail(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PostDetailScreen(post: post),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: AppTheme.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: GestureDetector(
              onTap: onOpenProfile,
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          post.authorDisplayName ?? 'Unknown',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          timeago.format(post.createdAt),
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (post.isBoosted)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.secondary.withOpacity(0.25),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'BOOSTED',
                        style: TextStyle(fontSize: 9, color: AppColors.secondary),
                      ),
                    ),
                  if (currentUserId != null && currentUserId == post.userId)
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, color: AppColors.textSecondary, size: 20),
                      onSelected: (value) {
                        if (value == 'delete') onDelete?.call();
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                          value: 'delete',
                          child: Text('Delete post'),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          if (post.caption.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Text(post.caption, style: const TextStyle(height: 1.3)),
            ),
          if (post.mediaUrl != null) ...[
            const SizedBox(height: 10),
            AspectRatio(
              aspectRatio: post.postType == PostType.video ? 9 / 16 : 4 / 5,
              child: CachedNetworkImage(
                imageUrl: post.thumbnailUrl ?? post.mediaUrl!,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(color: AppColors.surfaceBorder),
              ),
            ),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
            child: Row(
              children: [
                _actionButton(
                  icon: post.likedByMe ? Icons.favorite : Icons.favorite_border,
                  color: post.likedByMe ? AppColors.secondary : AppColors.textSecondary,
                  label: '${post.likeCount}',
                  onTap: onLike,
                ),
                const SizedBox(width: 18),
                _actionButton(
                  icon: Icons.mode_comment_outlined,
                  color: AppColors.textSecondary,
                  label: '${post.commentCount}',
                  onTap: onComment,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: color, fontSize: 13)),
        ],
      ),
    );
  }
}
