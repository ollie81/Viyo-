import 'package:flutter/material.dart';
import '../models/post.dart';
import '../services/post_service.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/post_card.dart';
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
    if (userId == null || userId == post.userId) return;
    if (post.likedByMe) {
      await PostService.unlikePost(userId, post.id);
    } else {
      await PostService.likePost(userId, post.id);
    }
    _load();
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
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : RefreshIndicator(
              onRefresh: _load,
              color: AppColors.primary,
              child: _posts.isEmpty
                  ? ListView(
                      children: const [
                        Padding(
                          padding: EdgeInsets.only(top: 100),
                          child: Center(
                            child: Text(
                              'No posts yet — be the first to share!',
                              style: TextStyle(color: AppColors.textSecondary),
                            ),
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
                      itemCount: _posts.length,
                      itemBuilder: (ctx, i) {
                        final post = _posts[i];
                        return PostCard(
                          post: post,
                          // Passing the logged-in userId lets PostCard show
                          // the delete menu only on the current user's posts.
                          currentUserId: SupabaseService.currentUserId,
                          onLike: () => _like(post),
                          onDelete: () => _delete(post),
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
