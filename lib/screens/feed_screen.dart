import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shimmer/shimmer.dart';
import '../models/post.dart';
import '../services/post_service.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/guest_gate.dart';
import '../widgets/home_header_section.dart';
import '../widgets/post_card.dart';
import 'ai_hub_screen.dart';
import 'notifications_screen.dart';
import 'post/post_detail_screen.dart';
import 'profile/profile_screen.dart';
import 'video_feed_screen.dart';

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  List<Post> _posts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final posts = await PostService.getFeed();
      if (!mounted) return;
      setState(() {
        _posts = posts;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _like(Post post) async {
    final userId = SupabaseService.currentUserId;
    if (userId == null) return;
    if (!await GuestGate.allow(context, action: 'like posts')) return;
    if (post.likedByMe) {
      await PostService.unlikePost(userId, post.id);
    } else {
      await PostService.likePost(userId, post.id);
    }
    await _load();
  }

  Future<void> _share(Post post) async {
    await Share.share(
      post.mediaUrl ?? post.caption,
      subject: 'Viyo post by ${post.authorUsername ?? 'creator'}',
    );
  }

  Future<void> _delete(Post post) async {
    // Guard: never show the delete dialog for posts the current user
    // doesn't own. This is belt-and-suspenders; the PostCard already
    // hides the menu unless currentUserId == post.userId.
    final userId = SupabaseService.currentUserId;
    if (userId == null || userId != post.userId) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete post?'),
        content: const Text("This can't be undone."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await PostService.deletePost(post);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: const Text(
          'Viyo',
          style: TextStyle(
            color: AppColors.primary,
            fontWeight: FontWeight.bold,
            fontSize: 22,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_awesome, color: AppColors.secondary),
            tooltip: 'AI Tools',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AiHubScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.play_circle_outline),
            tooltip: 'Shorts',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const VideoFeedScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const NotificationsScreen()),
            ),
          ),
        ],
      ),
      body: _loading
          ? const _FeedSkeleton()
          : RefreshIndicator(
              onRefresh: _load,
              color: AppColors.primary,
              child: _posts.isEmpty
                  ? ListView(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
                      children: const [
                        HomeHeaderSection(),
                        Padding(
                          padding: EdgeInsets.only(top: 70),
                          child: Center(
                            child: _EmptyFeedState(),
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
                      itemCount: _posts.length + 1,
                      itemBuilder: (ctx, i) {
                        if (i == 0) return const HomeHeaderSection();
                        final post = _posts[i - 1];
                        return PostCard(
                          post: post,
                          // Passing the logged-in userId lets PostCard show
                          // the delete menu only on the current user's posts.
                          currentUserId: SupabaseService.currentUserId,
                          onLike: () => _like(post),
                          onDelete: () => _delete(post),
                          onShare: () => _share(post),
                          onComment: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => PostDetailScreen(post: post),
                            ),
                          ),
                          onOpenMedia: post.postType == PostType.video
                              ? () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => VideoFeedScreen(
                                        initialPostId: post.id,
                                      ),
                                    ),
                                  )
                              : null,
                          onOpenProfile: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  ProfileScreen(userId: post.userId),
                            ),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}

/// Shown while the first page of the feed is loading — mimics the shape of
/// a couple of post cards instead of a bare spinner.
class _FeedSkeleton extends StatelessWidget {
  const _FeedSkeleton();

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppColors.surface,
      highlightColor: AppColors.surfaceBorder,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 3,
        itemBuilder: (_, __) => Container(
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const CircleAvatar(radius: 18, backgroundColor: Colors.white),
                    const SizedBox(width: 10),
                    Container(height: 12, width: 120, color: Colors.white),
                  ],
                ),
                const SizedBox(height: 14),
                AspectRatio(
                  aspectRatio: 4 / 5,
                  child: Container(color: Colors.white),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Empty-feed state — an icon-led nudge instead of a lone line of text,
/// since this is often the very first thing a new user sees.
class _EmptyFeedState extends StatelessWidget {
  const _EmptyFeedState();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.12),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.auto_awesome_outlined, color: AppColors.primary, size: 28),
        ),
        const SizedBox(height: 16),
        const Text(
          'No posts yet',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
        const SizedBox(height: 6),
        const Text(
          'Be the first to share — your AI coach\nreviews every post right after you do.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
        ),
      ],
    );
  }
}
