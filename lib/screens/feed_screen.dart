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
import 'messages/conversations_screen.dart';
import 'post/post_detail_screen.dart';
import 'profile/profile_screen.dart';
import 'video_feed_screen.dart';

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

/// Home feed tabs: For You (the existing hot-ranked feed), Videos and
/// AI Dramas (both just filters over that same pool — see PostService
/// .getFeed's own doc comment on why fetching everything and ranking
/// client-side is fine at this app's scale), and Following (a genuinely
/// different, separately-fetched query — a followed creator's post can
/// easily fall outside the For You pool entirely).
class _FeedScreenState extends State<FeedScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(length: 4, vsync: this);

  List<Post> _forYouPosts = [];
  List<Post> _followingPosts = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });

    // Each feed is fetched independently — one failing (e.g. a query
    // joining a table that isn't set up yet) shouldn't blank the other,
    // and swallowing both errors used to make a real failure look
    // exactly like "no posts yet" with no way to tell them apart.
    List<Post>? forYou;
    List<Post>? following;
    String? error;
    try {
      forYou = await PostService.getFeed();
    } catch (e) {
      debugPrint('getFeed failed: $e');
      error = '$e';
    }
    try {
      following = await PostService.getFollowingFeed();
    } catch (e) {
      debugPrint('getFollowingFeed failed: $e');
      error ??= '$e';
    }

    if (!mounted) return;
    setState(() {
      _forYouPosts = forYou ?? [];
      _followingPosts = following ?? [];
      _loading = false;
      _error = error;
    });
  }

  List<Post> get _videoPosts =>
      _forYouPosts.where((p) => p.postType == PostType.video).toList();

  List<Post> get _aiDramaPosts => _forYouPosts.where((p) => p.isEpisode).toList();

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
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update like: $e')),
      );
    }
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

  Widget _buildCard(Post post) {
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
          builder: (_) => ProfileScreen(userId: post.userId),
        ),
      ),
    );
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
            icon: const Icon(Icons.chat_bubble_outline),
            tooltip: 'Messages',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ConversationsScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const NotificationsScreen()),
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textMuted,
          indicatorColor: AppColors.primary,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(text: 'For You'),
            Tab(text: 'Videos'),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.auto_awesome, size: 14),
                  SizedBox(width: 5),
                  Text('Dramas'),
                ],
              ),
            ),
            Tab(text: 'Following'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _FeedTabBody(
            loading: _loading,
            error: _error,
            onRetry: _load,
            posts: _forYouPosts,
            onRefresh: _load,
            cardBuilder: _buildCard,
            showHeader: true,
            emptyState: const _EmptyFeedState(
              title: 'No posts yet',
              subtitle: 'Be the first to share — your AI coach\nreviews every post right after you do.',
              icon: Icons.auto_awesome_outlined,
            ),
          ),
          _FeedTabBody(
            loading: _loading,
            error: _error,
            onRetry: _load,
            posts: _videoPosts,
            onRefresh: _load,
            cardBuilder: _buildCard,
            emptyState: const _EmptyFeedState(
              title: 'No videos yet',
              subtitle: 'Videos posted to Viyo will show up here.',
              icon: Icons.videocam_outlined,
            ),
          ),
          _FeedTabBody(
            loading: _loading,
            error: _error,
            onRetry: _load,
            posts: _aiDramaPosts,
            onRefresh: _load,
            cardBuilder: _buildCard,
            emptyState: const _EmptyFeedState(
              title: 'No Dramas yet',
              subtitle: 'Upload one from the + button to start a series.',
              icon: Icons.auto_awesome,
            ),
          ),
          _FeedTabBody(
            loading: _loading,
            error: _error,
            onRetry: _load,
            posts: _followingPosts,
            onRefresh: _load,
            cardBuilder: _buildCard,
            emptyState: const _EmptyFeedState(
              title: 'Follow creators to see them here',
              subtitle: 'Posts from people you follow show up in this tab.',
              icon: Icons.people_outline,
            ),
          ),
        ],
      ),
    );
  }
}

/// One tab's content — a pull-to-refresh list of post cards, shared by
/// all four tabs above so the loading/empty/list wiring exists once.
class _FeedTabBody extends StatelessWidget {
  final bool loading;
  final String? error;
  final VoidCallback? onRetry;
  final List<Post> posts;
  final Future<void> Function() onRefresh;
  final Widget Function(Post) cardBuilder;
  final Widget emptyState;
  final bool showHeader;

  const _FeedTabBody({
    required this.loading,
    this.error,
    this.onRetry,
    required this.posts,
    required this.onRefresh,
    required this.cardBuilder,
    required this.emptyState,
    this.showHeader = false,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) return const _FeedSkeleton();

    // A load failure looks identical to a genuinely empty feed unless
    // called out — show what actually happened instead of "no posts yet"
    // when this tab's list is empty only because the fetch itself failed.
    final failedToLoad = posts.isEmpty && error != null;

    return RefreshIndicator(
      onRefresh: onRefresh,
      color: AppColors.primary,
      child: posts.isEmpty
          ? ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
              children: [
                if (showHeader) const HomeHeaderSection(),
                Padding(
                  padding: const EdgeInsets.only(top: 70),
                  child: Center(
                    child: failedToLoad
                        ? _FeedLoadError(message: error!, onRetry: onRetry)
                        : emptyState,
                  ),
                ),
              ],
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
              itemCount: posts.length + (showHeader ? 1 : 0),
              itemBuilder: (ctx, i) {
                if (showHeader) {
                  if (i == 0) return const HomeHeaderSection();
                  return cardBuilder(posts[i - 1]);
                }
                return cardBuilder(posts[i]);
              },
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

/// Shown instead of the empty state when the fetch itself failed, so a
/// real error (bad query, network, backend down) never looks identical
/// to "there's genuinely nothing here yet".
class _FeedLoadError extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const _FeedLoadError({required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: AppColors.danger.withOpacity(0.12),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.error_outline, color: AppColors.danger, size: 28),
        ),
        const SizedBox(height: 16),
        const Text(
          "Couldn't load this feed",
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5, height: 1.4),
          ),
        ),
        if (onRetry != null) ...[
          const SizedBox(height: 14),
          OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ],
    );
  }
}

/// Empty-tab state — an icon-led nudge instead of a lone line of text,
/// reused across all four feed tabs with a tab-specific message.
class _EmptyFeedState extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;

  const _EmptyFeedState({required this.title, required this.subtitle, required this.icon});

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
          child: Icon(icon, color: AppColors.primary, size: 28),
        ),
        const SizedBox(height: 16),
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
        ),
      ],
    );
  }
}
