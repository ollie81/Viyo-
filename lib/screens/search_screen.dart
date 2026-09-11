import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shimmer/shimmer.dart';
import '../models/post.dart';
import '../services/post_service.dart';
import '../services/profile_service.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import 'post/post_detail_screen.dart';
import 'post/viyo_post_viewer.dart';
import 'profile/profile_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _query = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  bool _loading = false;
  bool _hasQuery = false;
  Timer? _debounce;

  List<Map<String, dynamic>> _suggested = [];
  bool _loadingSuggested = true;

  List<Post> _discoverPosts = [];
  bool _loadingDiscover = true;

  @override
  void initState() {
    super.initState();
    _loadDefaults();
  }

  Future<void> _loadDefaults() async {
    await Future.wait([_loadSuggested(), _loadDiscover()]);
  }

  Future<void> _loadSuggested() async {
    final userId = SupabaseService.currentUserId;
    if (userId == null) {
      if (mounted) setState(() => _loadingSuggested = false);
      return;
    }
    try {
      final suggested = await ProfileService.getSuggestedCreators(excludeUserId: userId);
      if (!mounted) return;
      setState(() {
        _suggested = suggested;
        _loadingSuggested = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingSuggested = false);
    }
  }

  Future<void> _loadDiscover() async {
    try {
      final posts = await PostService.getDiscoverPosts();
      if (!mounted) return;
      setState(() {
        _discoverPosts = posts;
        _loadingDiscover = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingDiscover = false);
    }
  }

  void _onChanged(String value) {
    final hasQuery = value.trim().isNotEmpty;
    if (hasQuery != _hasQuery) setState(() => _hasQuery = hasQuery);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(value));
  }

  Future<void> _search(String value) async {
    if (value.trim().isEmpty) {
      setState(() => _results = []);
      return;
    }
    setState(() => _loading = true);
    final results = await ProfileService.searchCreators(value.trim());
    if (!mounted) return;
    setState(() {
      _results = results;
      _loading = false;
    });
  }

  Future<void> _openPost(int index) async {
    final media = _discoverPosts.map((p) => ViyoPostMedia.fromPost(p)).toList();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ViyoPostViewer(
          posts: media,
          initialIndex: index,
          onLikePost: _likePostById,
          onCommentPost: _commentPostById,
          onSharePost: _sharePostById,
        ),
      ),
    );
    if (mounted) _loadDiscover();
  }

  Future<void> _likePostById(String postId) async {
    final match = _discoverPosts.where((p) => p.id == postId);
    if (match.isEmpty) return;
    try {
      await PostService.toggleLike(match.first);
    } catch (_) {}
  }

  Future<void> _commentPostById(String postId) async {
    final match = _discoverPosts.where((p) => p.id == postId);
    if (match.isEmpty) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PostDetailScreen(post: match.first)),
    );
  }

  Future<void> _sharePostById(String postId) async {
    final match = _discoverPosts.where((p) => p.id == postId);
    if (match.isEmpty) return;
    final post = match.first;
    await Share.share(
      post.mediaUrl ?? post.caption,
      subject: 'Viyo post by ${post.authorUsername ?? 'creator'}',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: AppColors.background, title: const Text('Discover')),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Column(
          children: [
            TextField(
              controller: _query,
              onChanged: _onChanged,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'Search creators by name or username',
                prefixIcon: Icon(Icons.search, color: AppColors.textMuted),
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: !_hasQuery
                  ? RefreshIndicator(
                      onRefresh: _loadDefaults,
                      color: AppColors.primary,
                      child: _DiscoverBody(
                        loadingSuggested: _loadingSuggested,
                        suggested: _suggested,
                        loadingDiscover: _loadingDiscover,
                        posts: _discoverPosts,
                        onOpenPost: _openPost,
                      ),
                    )
                  : _loading
                      ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                      : _results.isEmpty
                          ? const _NoResultsState()
                          : ListView.builder(
                              itemCount: _results.length,
                              itemBuilder: (ctx, i) => _CreatorTile(creator: _results[i]),
                            ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The default (no search query) view: a compact row of suggested
/// creators above a masonry grid of trending posts — the grid is what
/// makes Discover feel alive the moment you open it, instead of asking
/// for a search first.
class _DiscoverBody extends StatelessWidget {
  final bool loadingSuggested;
  final List<Map<String, dynamic>> suggested;
  final bool loadingDiscover;
  final List<Post> posts;
  final void Function(int index) onOpenPost;

  const _DiscoverBody({
    required this.loadingSuggested,
    required this.suggested,
    required this.loadingDiscover,
    required this.posts,
    required this.onOpenPost,
  });

  @override
  Widget build(BuildContext context) {
    if (loadingDiscover) return const _DiscoverSkeleton();

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (!loadingSuggested && suggested.isNotEmpty) ...[
          const _SectionLabel('SUGGESTED CREATORS'),
          SizedBox(
            height: 92,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: suggested.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (ctx, i) => _SuggestedCreatorChip(creator: suggested[i]),
            ),
          ),
          const SizedBox(height: 18),
        ],
        if (posts.isEmpty)
          const _EmptyDiscoverState()
        else ...[
          const _SectionLabel('TRENDING NOW'),
          const SizedBox(height: 10),
          MasonryGridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            itemCount: posts.length,
            itemBuilder: (ctx, i) => _DiscoverTile(
              post: posts[i],
              // Cycles tile heights for a Pinterest-style staggered look
              // instead of a uniform grid — video posts stay tall
              // (they're already a 9:16 thumbnail) so this only varies
              // photo tiles.
              tall: posts[i].postType == PostType.video || i % 3 == 1,
              onTap: () => onOpenPost(i),
            ),
          ),
        ],
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          letterSpacing: 1.2,
          color: AppColors.textMuted,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _SuggestedCreatorChip extends StatelessWidget {
  final Map<String, dynamic> creator;
  const _SuggestedCreatorChip({required this.creator});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ProfileScreen(userId: creator['id'])),
      ),
      child: SizedBox(
        width: 68,
        child: Column(
          children: [
            CircleAvatar(
              radius: 30,
              backgroundColor: AppColors.surfaceBorder,
              backgroundImage:
                  creator['avatar_url'] != null ? CachedNetworkImageProvider(creator['avatar_url']) : null,
              child: creator['avatar_url'] == null
                  ? Text((creator['display_name'] ?? '?')[0].toUpperCase())
                  : null,
            ),
            const SizedBox(height: 6),
            Text(
              '@${creator['username'] ?? ''}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _DiscoverTile extends StatelessWidget {
  final Post post;
  final bool tall;
  final VoidCallback onTap;

  const _DiscoverTile({required this.post, required this.tall, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: AspectRatio(
          aspectRatio: tall ? 9 / 15 : 3 / 4,
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
                  child: const Icon(Icons.broken_image_outlined, color: AppColors.textMuted),
                ),
              ),
              // Bottom gradient so the like-count/caption row stays legible
              // over any thumbnail, bright or dark.
              const Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 56,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black87],
                    ),
                  ),
                ),
              ),
              if (post.postType == PostType.video)
                const Positioned(
                  top: 8,
                  right: 8,
                  child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
                ),
              if (post.isBoosted)
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.secondary.withOpacity(0.85),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'BOOSTED',
                      style: TextStyle(fontSize: 8.5, color: Colors.white, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              Positioned(
                left: 8,
                right: 8,
                bottom: 7,
                child: Row(
                  children: [
                    const Icon(Icons.favorite, size: 13, color: Colors.white),
                    const SizedBox(width: 4),
                    Text(
                      '${post.likeCount}',
                      style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '@${post.authorUsername ?? ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: const TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CreatorTile extends StatelessWidget {
  final Map<String, dynamic> creator;

  const _CreatorTile({required this.creator});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: AppColors.surfaceBorder,
        backgroundImage:
            creator['avatar_url'] != null ? NetworkImage(creator['avatar_url']) : null,
        child: creator['avatar_url'] == null
            ? Text((creator['display_name'] ?? '?')[0].toUpperCase())
            : null,
      ),
      title: Text(creator['display_name'] ?? ''),
      subtitle: Text(
        '@${creator['username']}${creator['niche'] != null && creator['niche'] != '' ? ' · ${creator['niche']}' : ''}',
        style: const TextStyle(color: AppColors.textMuted),
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ProfileScreen(userId: creator['id'])),
      ),
    );
  }
}

class _EmptyDiscoverState extends StatelessWidget {
  const _EmptyDiscoverState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 60),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.explore_outlined, color: AppColors.primary, size: 26),
            ),
            const SizedBox(height: 14),
            const Text('Nothing to discover yet', style: TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 4),
            const Text(
              'Be the first to post something',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoResultsState extends StatelessWidget {
  const _NoResultsState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('No creators found', style: TextStyle(color: AppColors.textMuted)),
    );
  }
}

/// Shown while Discover's post grid + suggested creators load — mimics
/// the real layout (a creator strip above a staggered tile grid).
class _DiscoverSkeleton extends StatelessWidget {
  const _DiscoverSkeleton();

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppColors.surface,
      highlightColor: AppColors.surfaceBorder,
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          SizedBox(
            height: 92,
            child: Row(
              children: List.generate(
                5,
                (_) => const Padding(
                  padding: EdgeInsets.only(right: 12),
                  child: CircleAvatar(radius: 30, backgroundColor: Colors.white),
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          MasonryGridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            itemCount: 8,
            itemBuilder: (ctx, i) => AspectRatio(
              aspectRatio: i % 3 == 1 ? 9 / 15 : 3 / 4,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Container(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
