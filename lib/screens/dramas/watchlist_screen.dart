import 'package:flutter/material.dart';
import '../../models/post.dart';
import '../../models/series.dart';
import '../../services/post_service.dart';
import '../../services/supabase_service.dart';
import '../../services/watchlist_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/guest_gate.dart';
import '../../widgets/post_card.dart';
import '../../widgets/series_poster_card.dart';
import '../post/post_detail_screen.dart';
import '../post/series_detail_screen.dart';
import '../profile/profile_screen.dart';
import '../video_feed_screen.dart';

/// Everything the signed-in viewer has saved via WatchlistButton — a
/// series grid above a post list, since those are the two target types
/// the `watchlist` table holds. Sign-in is guaranteed by the time this
/// screen is reachable (every entry point requires it), so no guest
/// empty-state branch is needed here the way GuestGate handles it
/// inline elsewhere.
class WatchlistScreen extends StatefulWidget {
  const WatchlistScreen({super.key});

  @override
  State<WatchlistScreen> createState() => _WatchlistScreenState();
}

class _WatchlistScreenState extends State<WatchlistScreen> {
  List<Series> _series = [];
  List<Post> _posts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final userId = SupabaseService.currentUserId;
    if (userId == null) {
      setState(() => _loading = false);
      return;
    }
    setState(() => _loading = true);
    final results = await Future.wait([
      WatchlistService.getSavedSeries(userId),
      WatchlistService.getSavedPosts(userId),
    ]);
    if (!mounted) return;
    setState(() {
      _series = results[0] as List<Series>;
      _posts = results[1] as List<Post>;
      _loading = false;
    });
  }

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
      _load();
    } catch (_) {
      // Best-effort — a failed like here isn't worth a snackbar on a
      // screen the viewer opened to browse saved items, not to like.
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEmpty = _series.isEmpty && _posts.isEmpty;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: const Text('My Watchlist'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.secondary))
          : isEmpty
              ? _emptyState()
              : RefreshIndicator(
                  onRefresh: _load,
                  color: AppColors.secondary,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                    children: [
                      if (_series.isNotEmpty) ...[
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 4),
                          child: Text(
                            'SERIES',
                            style: TextStyle(fontSize: 11, letterSpacing: 0.8, color: AppColors.textMuted, fontWeight: FontWeight.w700),
                          ),
                        ),
                        const SizedBox(height: 10),
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 16,
                            crossAxisSpacing: 12,
                            childAspectRatio: 0.6,
                          ),
                          itemCount: _series.length,
                          itemBuilder: (_, i) => SeriesPosterCard(
                            series: _series[i],
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => SeriesDetailScreen(series: _series[i])),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                      if (_posts.isNotEmpty) ...[
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 4),
                          child: Text(
                            'POSTS',
                            style: TextStyle(fontSize: 11, letterSpacing: 0.8, color: AppColors.textMuted, fontWeight: FontWeight.w700),
                          ),
                        ),
                        const SizedBox(height: 10),
                        ..._posts.map((post) => PostCard(
                              post: post,
                              currentUserId: SupabaseService.currentUserId,
                              onLike: () => _like(post),
                              onComment: () => Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => PostDetailScreen(post: post)),
                              ),
                              onOpenMedia: post.postType == PostType.video
                                  ? () => Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => VideoFeedScreen(
                                            initialPostId: post.id,
                                            seriesId: post.isEpisode ? post.seriesId : null,
                                          ),
                                        ),
                                      )
                                  : null,
                              onOpenProfile: () => Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => ProfileScreen(userId: post.userId)),
                              ),
                            )),
                      ],
                    ],
                  ),
                ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.12), shape: BoxShape.circle),
              child: const Icon(Icons.bookmark_border_rounded, color: AppColors.primary, size: 28),
            ),
            const SizedBox(height: 16),
            const Text('Your watchlist is waiting', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 6),
            const Text(
              'Tap the bookmark on a series or post to save it here for later.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}
