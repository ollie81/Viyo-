import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:share_plus/share_plus.dart';
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
  final VoidCallback? onShare;
  final VoidCallback? onOpenMedia;

  /// When true (default), tapping the media opens PostDetailScreen.
  /// Set to false when PostCard is already inside PostDetailScreen to
  /// prevent navigating to a second copy of the same screen.
  final bool enableMediaTap;

  const PostCard({
    super.key,
    required this.post,
    required this.onLike,
    required this.onComment,
    this.onOpenProfile,
    this.currentUserId,
    this.onDelete,
    this.onShare,
    this.onOpenMedia,
    this.enableMediaTap = true,
  });

  void _openPostDetail(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PostDetailScreen(post: post)),
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
          // ── Header: avatar + name + time + overflow menu ──
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
                        ? Text(
                            (post.authorDisplayName ?? '?')[0].toUpperCase(),
                            style: const TextStyle(fontSize: 13),
                          )
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
                  // Only the post owner sees the delete option.
                  // The ownership check here is a UX convenience; the real
                  // enforcement is Supabase RLS on the posts table.
                  if (currentUserId != null && currentUserId == post.userId)
                    PopupMenuButton<String>(
                      icon: const Icon(
                        Icons.more_vert,
                        color: AppColors.textSecondary,
                        size: 20,
                      ),
                      onSelected: (value) {
                        if (value == 'delete') onDelete?.call();
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                              SizedBox(width: 8),
                              Text('Delete post'),
                            ],
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),

          // ── Caption ──
          if (post.caption.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              child: Text(post.caption, style: const TextStyle(height: 1.3)),
            ),

          // ── Media (photo or video thumbnail) ──
          if (post.mediaUrl != null) ...[
            GestureDetector(
              onTap: enableMediaTap
                  ? (onOpenMedia ?? () => _openPostDetail(context))
                  : null,
              child: AspectRatio(
                aspectRatio: post.postType == PostType.video ? 9 / 16 : 4 / 5,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CachedNetworkImage(
                      imageUrl: post.thumbnailUrl ?? post.mediaUrl!,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Shimmer.fromColors(
                        baseColor: AppColors.surfaceBorder,
                        highlightColor: AppColors.surface,
                        child: Container(color: Colors.white),
                      ),
                      errorWidget: (_, __, ___) => Container(
                        color: AppColors.surfaceBorder,
                        child: const Icon(
                          Icons.broken_image_outlined,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                    // Play button overlay on video posts so creators
                    // always know a post is a video at a glance.
                    if (post.postType == PostType.video)
                      Center(
                        child: Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.55),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 34,
                          ),
                        ),
                      ),
                    // Duration badge for videos
                    if (post.postType == PostType.video &&
                        post.durationSeconds != null)
                      Positioned(
                        bottom: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.65),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            _fmtDuration(post.durationSeconds!),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],

          // ── Action bar: like + comment ──
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
            child: Row(
              children: [
                _likeButton(),
                const SizedBox(width: 18),
                _actionButton(
                  icon: Icons.mode_comment_outlined,
                  color: AppColors.textSecondary,
                  label: '${post.commentCount}',
                  onTap: onComment,
                ),
                const SizedBox(width: 18),
                _actionButton(
                  icon: Icons.ios_share_outlined,
                  color: AppColors.textSecondary,
                  label: 'Share',
                  onTap: onShare ?? () => Share.share(
                    post.mediaUrl ?? post.caption,
                    subject: 'Viyo post by ${post.authorUsername ?? 'creator'}',
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'More',
                  visualDensity: VisualDensity.compact,
                  onPressed: () {},
                  icon: const Icon(Icons.bookmark_border_rounded,
                      color: AppColors.textSecondary, size: 21),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _fmtDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  /// The like button gets its own widget (rather than going through
  /// _actionButton) so the heart can "pop" on tap — the single most
  /// frequent interaction in the app deserves feedback beyond a color swap.
  Widget _likeButton() {
    final color = post.likedByMe ? AppColors.secondary : AppColors.textSecondary;
    return GestureDetector(
      onTap: onLike,
      child: Row(
        children: [
          TweenAnimationBuilder<double>(
            key: ValueKey(post.likedByMe),
            tween: Tween(begin: post.likedByMe ? 1.4 : 1.0, end: 1.0),
            duration: const Duration(milliseconds: 280),
            curve: Curves.elasticOut,
            builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
            child: Icon(
              post.likedByMe ? Icons.favorite : Icons.favorite_border,
              size: 20,
              color: color,
            ),
          ),
          const SizedBox(width: 6),
          Text('${post.likeCount}', style: TextStyle(color: color, fontSize: 13)),
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
