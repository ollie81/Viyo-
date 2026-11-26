import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:shimmer/shimmer.dart';
import '../models/post.dart';
import '../models/series.dart';
import '../services/post_service.dart';
import '../services/profile_service.dart';
import '../services/series_service.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/comments_sheet.dart';
import '../widgets/retryable_network_image.dart';
import '../widgets/series_poster_card.dart';
import 'post/series_detail_screen.dart';
import 'post/viyo_post_viewer.dart';
import 'profile/profile_screen.dart';
import 'video_feed_screen.dart';
import '../services/share_links.dart';
import '../services/discover_service.dart';
import '../services/promotion_service.dart';
import '../widgets/ad_post_extras.dart';
import '../widgets/web_ad_card.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _query = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  List<Post> _titles = [];
  List<String> _understood = [];
  bool _loading = false;
  bool _hasQuery = false;
  Timer? _debounce;

  List<Map<String, dynamic>> _suggested = [];
  bool _loadingSuggested = true;

  List<Post> _discoverPosts = [];
  bool _loadingDiscover = true;

  DiscoverCategory _category = DiscoverCategory.forYou;

  List<Post> _trendingDramas = [];
  List<Series> _newSeries = [];
  bool _loadingDramas = true;

  @override
  void initState() {
    super.initState();
    _loadDefaults();
  }

  Future<void> _loadDefaults() async {
    await Future.wait([_loadSuggested(), _loadDiscover(), _loadAiDramas()]);
  }

  Future<void> _loadAiDramas() async {
    try {
      final results = await Future.wait([
        SeriesService.getTrendingAiDramas(),
        SeriesService.getNewAiSeries(),
        ServerDiscovery.trending(),
      ]);
      if (!mounted) return;
      // Trending from the server (distinct viewers, quality, fairness to smaller creators) when it has enough
      // activity to say; otherwise the original list.
      final server = results[2] as TrendingSections?;
      final serverDramas = server?.trending.where((p) => p.seriesId != null).toList() ?? const <Post>[];
      setState(() {
        _trendingDramas = serverDramas.isNotEmpty ? serverDramas : results[0] as List<Post>;
        _newSeries = results[1] as List<Series>;
        _loadingDramas = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingDramas = false);
    }
  }

  Future<void> _loadSuggested() async {
    final userId = SupabaseService.currentUserId;
    if (userId == null) {
      if (mounted) setState(() => _loadingSuggested = false);
      return;
    }
    try {
      final suggested =
          await ProfileService.getSuggestedCreators(excludeUserId: userId);
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
      final mixed = await DiscoverService.withPromotions(DiscoverService.capAds(posts), 'for_you');
      if (!mounted) return;
      setState(() {
        // For You: ads stay a small, spaced-out part of the mix (all of them are in the Ads category); paid
        // promotions take at most two labelled places.
        _discoverPosts = mixed;
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
    // Dramas, movies, videos and creators from the server's search (typos, partial words, described stories);
    // the original creator search if it can't be reached.
    final server = await ServerDiscovery.search(value.trim());
    final results = server?.creators ?? await ProfileService.searchCreators(value.trim());
    if (!mounted || _query.text.trim() != value.trim()) return;
    setState(() {
      _results = results;
      _titles = server?.titles ?? [];
      _understood = server?.understoodGenres ?? [];
      _loading = false;
    });
  }

  Future<void> _openResult(Post p) async {
    if (p.seriesId != null) {
      final series = await SeriesService.getSeries(p.seriesId!);
      if (series != null && mounted) {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => SeriesDetailScreen(series: series)));
      }
      return;
    }
    if (p.mediaUrl == null) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ViyoPostViewer(posts: [ViyoPostMedia.fromPost(p)], initialIndex: 0),
    ));
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
    // A bottom sheet, not a full navigation — same fix as the video
    // feed: ViyoPostViewer's video/photo page has no way to know it's
    // been covered by a full-screen route pushed on top of it (the
    // PageView here never changes pages either), so a MaterialPageRoute
    // left it stuck playing invisibly underneath. showCommentsSheet is a
    // translucent overlay, so the page underneath stays visible instead.
    await showCommentsSheet(context, match.first);
  }

  Future<void> _sharePostById(String postId) async {
    final match = _discoverPosts.where((p) => p.id == postId);
    if (match.isEmpty) return;
    await ShareLinks.sharePost(match.first);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // No title bar: the Discover tab in the bottom menu already says where
      // you are, so the search box sits at the top and content gets the room.
      body: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Column(
            children: [
              SizedBox(
                height: 40,
                child: TextField(
                  controller: _query,
                  onChanged: _onChanged,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  textAlignVertical: TextAlignVertical.center,
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'Search dramas, movies, creators',
                    hintStyle:
                        TextStyle(color: AppColors.textMuted, fontSize: 14),
                    prefixIcon: Icon(Icons.search,
                        color: AppColors.textMuted, size: 20),
                    prefixIconConstraints:
                        BoxConstraints(minWidth: 40, minHeight: 40),
                    contentPadding:
                        EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              if (!_hasQuery) ...[
                _CategoryBar(
                  selected: _category,
                  onSelect: (c) => setState(() => _category = c),
                ),
                const SizedBox(height: 10),
              ],
              Expanded(
                child: !_hasQuery && _category != DiscoverCategory.forYou
                    ? _CategoryFeed(key: ValueKey(_category), category: _category)
                    : !_hasQuery
                    ? RefreshIndicator(
                        onRefresh: _loadDefaults,
                        color: AppColors.primary,
                        child: _DiscoverBody(
                          loadingSuggested: _loadingSuggested,
                          suggested: _suggested,
                          loadingDiscover: _loadingDiscover,
                          posts: _discoverPosts,
                          onOpenPost: _openPost,
                          loadingDramas: _loadingDramas,
                          trendingDramas: _trendingDramas,
                          newSeries: _newSeries,
                          onOpenDrama: (post) => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => VideoFeedScreen(
                                initialPostId: post.id,
                                seriesId: post.seriesId,
                              ),
                            ),
                          ),
                          onOpenSeries: (series) => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) =>
                                    SeriesDetailScreen(series: series)),
                          ),
                        ),
                      )
                    : _loading
                        ? const Center(
                            child: CircularProgressIndicator(
                                color: AppColors.primary))
                        : _results.isEmpty && _titles.isEmpty
                            ? const _NoResultsState()
                            : ListView(
                                padding: EdgeInsets.only(bottom: 24 + MediaQuery.paddingOf(context).bottom),
                                children: [
                                  if (_understood.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: Text('Showing ${_understood.join(', ')} stories',
                                          style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                                    ),
                                  if (_titles.isNotEmpty) const _SectionLabel('DRAMAS, MOVIES & VIDEOS'),
                                  for (final t in _titles) _TitleResult(post: t, onTap: () => _openResult(t)),
                                  if (_results.isNotEmpty) ...[
                                    const SizedBox(height: 10),
                                    const _SectionLabel('CREATORS'),
                                    for (final c in _results) _CreatorTile(creator: c),
                                  ],
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
  final bool loadingDramas;
  final List<Post> trendingDramas;
  final List<Series> newSeries;
  final void Function(Post) onOpenDrama;
  final void Function(Series) onOpenSeries;

  const _DiscoverBody({
    required this.loadingSuggested,
    required this.suggested,
    required this.loadingDiscover,
    required this.posts,
    required this.onOpenPost,
    required this.loadingDramas,
    required this.trendingDramas,
    required this.newSeries,
    required this.onOpenDrama,
    required this.onOpenSeries,
  });

  @override
  Widget build(BuildContext context) {
    if (loadingDiscover) return const _DiscoverSkeleton();

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      // Clears HomeShell's floating nav (reported as bottom padding).
      padding:
          EdgeInsets.only(bottom: 24 + MediaQuery.paddingOf(context).bottom),
      children: [
        if (!loadingSuggested && suggested.isNotEmpty) ...[
          const _SectionLabel('SUGGESTED CREATORS'),
          SizedBox(
            height: 92,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: suggested.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (ctx, i) =>
                  _SuggestedCreatorChip(creator: suggested[i]),
            ),
          ),
          const SizedBox(height: 18),
        ],
        // Both drama sections below are a real 2-column grid, not a
        // horizontally-scrolling single row — with only a handful of
        // series/episodes existing so far, a narrow row of cards just
        // floats in a mostly-empty strip with the rest of the screen's
        // width unused. A grid puts that same content at roughly double
        // the width per card and wraps onto more rows as more shows up,
        // instead of requiring a sideways scroll to see more.
        if (!loadingDramas && newSeries.isNotEmpty) ...[
          const _SectionLabel('NEW SERIES',
              icon: Icons.auto_awesome, color: AppColors.secondary),
          const SizedBox(height: 10),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 14,
              crossAxisSpacing: 12,
              childAspectRatio: 0.6,
            ),
            itemCount: newSeries.length,
            itemBuilder: (ctx, i) => SeriesPosterCard(
              series: newSeries[i],
              onTap: () => onOpenSeries(newSeries[i]),
            ),
          ),
          const SizedBox(height: 18),
        ],
        if (!loadingDramas && trendingDramas.isNotEmpty) ...[
          const _SectionLabel('TRENDING DRAMAS',
              icon: Icons.auto_awesome, color: AppColors.secondary),
          const SizedBox(height: 10),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.72,
            ),
            itemCount: trendingDramas.length,
            itemBuilder: (ctx, i) => _TrendingDramaCard(
              post: trendingDramas[i],
              rank: i + 1,
              onTap: () => onOpenDrama(trendingDramas[i]),
            ),
          ),
          const SizedBox(height: 18),
        ],
        if (posts.isEmpty)
          const _EmptyDiscoverState()
        else ...[
          // Web only: one labelled ad between sections, never on a tile or a video.
          const WebAdCard(placement: 'discover', kind: WebAdKind.infeed, margin: EdgeInsets.only(bottom: 18)),
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
  final IconData? icon;
  final Color? color;
  const _SectionLabel(this.text, {this.icon, this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color ?? AppColors.textMuted),
            const SizedBox(width: 6),
          ],
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 1.2,
              color: color ?? AppColors.textMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// A trending AI Short Drama episode — same shape as _DiscoverTile but
/// carries the series badge, matching the sparkle treatment used
/// everywhere else an episode appears in the app.
class _TrendingDramaCard extends StatelessWidget {
  final Post post;
  final VoidCallback onTap;
  // This row is already sorted by the same engagement score that
  // decides its order, so a #1/#2/#3 badge is just labeling a ranking
  // that already exists — not inventing one. Shown for every tile
  // (matching the ranked-grid density of competitor drama apps), gold
  // for the top 3 to call those out the way a real leaderboard would.
  final int rank;
  const _TrendingDramaCard(
      {required this.post, required this.onTap, required this.rank});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 130,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.secondary.withOpacity(0.3)),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (post.thumbnailUrl != null)
              RetryableNetworkImage(
                imageUrl: post.thumbnailUrl!,
                fit: BoxFit.cover,
                memCacheWidth: 400,
                errorWidget: (_, __, ___) => Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppColors.secondary.withOpacity(0.22),
                        AppColors.surface
                      ],
                    ),
                  ),
                ),
              )
            else
              // No thumbnail — never fall back to loading post.mediaUrl
              // (the raw video file) through this image widget; see
              // post_card.dart's own identical fix for why.
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.secondary.withOpacity(0.22),
                      AppColors.surface
                    ],
                  ),
                ),
              ),
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black87, Colors.transparent],
                  ),
                ),
                child: SizedBox(height: 40),
              ),
            ),
            Positioned(
              top: 6,
              left: 6,
              right: 6,
              child: Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: rank <= 3
                          ? AppColors.coin
                          : Colors.black.withOpacity(0.55),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '#$rank',
                      style: TextStyle(
                        color: rank <= 3 ? AppColors.background : Colors.white,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 5),
                  const Icon(Icons.auto_awesome,
                      size: 11, color: AppColors.secondary),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Ep ${post.episodeNumber ?? ''}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(8, 20, 8, 8),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black87],
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      post.seriesTitle ?? 'Short Drama',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          height: 1.2),
                    ),
                    if (post.viewCount > 0) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          const Icon(Icons.visibility_outlined,
                              size: 10, color: Colors.white70),
                          const SizedBox(width: 3),
                          Text(
                            _compactCount(post.viewCount),
                            style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "1.2K"/"3.4M"-style compact count for a tile's view/engagement
/// badge — raw numbers like 48213 read as clutter at this tile size,
/// where the competitor reference this row is matching always
/// abbreviates.
String _compactCount(int n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
  return '$n';
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
              backgroundImage: creator['avatar_url'] != null
                  ? CachedNetworkImageProvider(creator['avatar_url'])
                  : null,
              child: creator['avatar_url'] == null
                  ? Text((creator['display_name'] ?? '?')[0].toUpperCase())
                  : null,
            ),
            const SizedBox(height: 6),
            Text(
              '@${creator['username'] ?? ''}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(fontSize: 11, color: AppColors.textSecondary),
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

  const _DiscoverTile(
      {required this.post, required this.tall, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tile = _tile();
    final promo = post.promotionId;
    return promo == null ? tile : SeenOnScreen(onSeen: () => PromotionService.recordImpression(promo), child: tile);
  }

  Widget _tile() {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: AspectRatio(
          aspectRatio: tall ? 9 / 15 : 3 / 4,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (post.thumbnailUrl != null)
                RetryableNetworkImage(
                  imageUrl: post.thumbnailUrl!,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Shimmer.fromColors(
                    baseColor: AppColors.surfaceBorder,
                    highlightColor: AppColors.surface,
                    child: Container(color: Colors.white),
                  ),
                )
              else
                // No thumbnail — never fall back to loading post.mediaUrl
                // (the raw video file) through this image widget; see
                // post_card.dart's own identical fix for why.
                Container(
                  color: AppColors.surfaceBorder,
                  child: const Icon(
                    Icons.movie_outlined,
                    color: AppColors.textMuted,
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
                  child: Icon(Icons.play_arrow_rounded,
                      color: Colors.white, size: 20),
                ),
              if (post.isAd || post.isPromoted)
                Positioned(
                  top: 8,
                  left: 8,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (post.isAd) const AdLabel(),
                    if (post.isAd && post.isPromoted) const SizedBox(width: 4),
                    // Paid placement is always labelled as such.
                    if (post.isPromoted)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.secondary.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'PROMOTED',
                          style: TextStyle(
                              fontSize: 8.5,
                              color: Colors.white,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                  ]),
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
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '@${post.authorUsername ?? ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 11),
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
        backgroundImage: creator['avatar_url'] != null
            ? NetworkImage(creator['avatar_url'])
            : null,
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
              child: const Icon(Icons.explore_outlined,
                  color: AppColors.primary, size: 26),
            ),
            const SizedBox(height: 14),
            const Text('Nothing to discover yet',
                style: TextStyle(color: AppColors.textSecondary)),
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
      child: Text('No creators found',
          style: TextStyle(color: AppColors.textMuted)),
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
                  child:
                      CircleAvatar(radius: 30, backgroundColor: Colors.white),
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


/// The category chips under the search box. One row, scrolls sideways on narrow phones.
class _CategoryBar extends StatelessWidget {
  final DiscoverCategory selected;
  final ValueChanged<DiscoverCategory> onSelect;
  const _CategoryBar({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: DiscoverCategory.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final c = DiscoverCategory.values[i];
          final on = c == selected;
          return ChoiceChip(
            label: Text(c.label),
            selected: on,
            showCheckmark: false,
            visualDensity: VisualDensity.compact,
            labelStyle: TextStyle(
              fontSize: 12.5,
              fontWeight: on ? FontWeight.w800 : FontWeight.w600,
              color: on ? Colors.black : AppColors.textSecondary,
            ),
            selectedColor: AppColors.primary,
            backgroundColor: AppColors.surface,
            side: BorderSide(color: on ? AppColors.primary : AppColors.surfaceBorder),
            onSelected: (_) => onSelect(c),
          );
        },
      ),
    );
  }
}

/// One category's page: Shorts and Ads as a 2-column grid of video tiles, Photos as a 3-column square grid,
/// Movies and Dramas as poster grids that open the series page. Loads more as you scroll; pull to refresh.
class _CategoryFeed extends StatefulWidget {
  final DiscoverCategory category;
  const _CategoryFeed({super.key, required this.category});

  @override
  State<_CategoryFeed> createState() => _CategoryFeedState();
}

class _CategoryFeedState extends State<_CategoryFeed> {
  final _scroll = ScrollController();
  List<Post> _posts = [];
  List<Series> _series = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;
  String? _adCategory;
  int _fetched = 0; // rows read so far (some can be filtered out, e.g. blocked creators)

  DiscoverCategory get _cat => widget.category;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 600) _loadMore();
    });
    _reload();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
      _hasMore = true;
      _fetched = 0;
    });
    try {
      if (_cat.isSeries) {
        final s = await DiscoverService.series(_cat);
        if (!mounted) return;
        setState(() {
          _series = s;
          _hasMore = s.length >= DiscoverService.pageSize;
        });
      } else {
        var p = await DiscoverService.posts(_cat, adCategory: _adCategory);
        if (_cat == DiscoverCategory.ads) p = await DiscoverService.withPromotions(p, 'ads', adCategory: _adCategory);
        if (!mounted) return;
        setState(() {
          _posts = p;
          _fetched = DiscoverService.pageSize;
          _hasMore = p.isNotEmpty;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = "Couldn't load ${_cat.label.toLowerCase()}. Check your connection.");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore || _error != null) return;
    setState(() => _loadingMore = true);
    try {
      if (_cat.isSeries) {
        final more = await DiscoverService.series(_cat, limit: _series.length + DiscoverService.pageSize);
        if (!mounted) return;
        setState(() {
          _hasMore = more.length > _series.length;
          _series = more;
        });
      } else {
        final more = await DiscoverService.posts(_cat, offset: _fetched, adCategory: _adCategory);
        if (!mounted) return;
        final seen = _posts.map((p) => p.id).toSet();
        setState(() {
          _fetched += DiscoverService.pageSize;
          _posts = [..._posts, ...more.where((p) => !seen.contains(p.id))];
          _hasMore = more.isNotEmpty;
        });
      }
    } catch (_) {
      // Keep what's shown; scrolling again retries.
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _openPost(int index) async {
    final media = _posts.map((p) => ViyoPostMedia.fromPost(p)).toList();
    Post? find(String id) => _posts.where((p) => p.id == id).firstOrNull;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ViyoPostViewer(
        posts: media,
        initialIndex: index,
        onLikePost: (id) async {
          final p = find(id);
          if (p != null) {
            try {
              await PostService.toggleLike(p);
            } catch (_) {}
          }
        },
        onCommentPost: (id) async {
          final p = find(id);
          if (p != null) await showCommentsSheet(context, p);
        },
        onSharePost: (id) async {
          final p = find(id);
          if (p != null) await ShareLinks.sharePost(p);
        },
      ),
    ));
  }

  static const _adAfterCards = 6;

  String get _emptyText => switch (_cat) {
        DiscoverCategory.shorts => 'No shorts yet',
        DiscoverCategory.movies => 'No movies yet',
        DiscoverCategory.dramas => 'No dramas yet',
        DiscoverCategory.ads => _adCategory == null ? 'No ads published yet' : 'No ads in this category yet',
        DiscoverCategory.photos => 'No photos yet',
        DiscoverCategory.forYou => 'Nothing to discover yet',
      };

  @override
  Widget build(BuildContext context) {
    final bottom = 24 + MediaQuery.paddingOf(context).bottom;
    final filters = _cat == DiscoverCategory.ads ? _adFilters() : null;
    if (_loading) {
      return Column(children: [if (filters != null) filters, const Expanded(child: _DiscoverSkeleton())]);
    }
    if (_error != null) {
      return Column(children: [
        if (filters != null) filters,
        Expanded(
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: 10),
              OutlinedButton(onPressed: _reload, child: const Text('Try again')),
            ]),
          ),
        ),
      ]);
    }
    final empty = _cat.isSeries ? _series.isEmpty : _posts.isEmpty;
    Widget grid;
    if (empty) {
      grid = ListView(physics: const AlwaysScrollableScrollPhysics(), children: [
        Padding(
          padding: const EdgeInsets.only(top: 80),
          child: Center(child: Text(_emptyText, style: const TextStyle(color: AppColors.textMuted))),
        ),
      ]);
    } else if (_cat.isSeries) {
      // Movies / Dramas: the poster grid, with one in-feed ad card (web only) spanning the row after the first
      // [_adAfterCards] posters, never on a poster.
      const delegate = SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 14,
        crossAxisSpacing: 12,
        childAspectRatio: 0.6,
      );
      Widget poster(int i) => SeriesPosterCard(
            series: _series[i],
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => SeriesDetailScreen(series: _series[i])),
            ),
          );
      final split = _series.length > _adAfterCards ? _adAfterCards : _series.length;
      grid = CustomScrollView(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverGrid(delegate: SliverChildBuilderDelegate((_, i) => poster(i), childCount: split), gridDelegate: delegate),
          if (_series.length > _adAfterCards) ...[
            SliverToBoxAdapter(
              child: WebAdCard(
                placement: 'discover-${_cat.name}',
                kind: WebAdKind.infeed,
                margin: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
            SliverGrid(
              delegate: SliverChildBuilderDelegate((_, i) => poster(split + i), childCount: _series.length - split),
              gridDelegate: delegate,
            ),
          ],
          SliverPadding(padding: EdgeInsets.only(bottom: bottom)),
        ],
      );
    } else if (_cat == DiscoverCategory.photos) {
      grid = GridView.builder(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(bottom: bottom),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 3,
          crossAxisSpacing: 3,
        ),
        itemCount: _posts.length,
        itemBuilder: (_, i) => GestureDetector(
          onTap: () => _openPost(i),
          child: (_posts[i].thumbnailUrl ?? _posts[i].mediaUrl) != null
              ? RetryableNetworkImage(
                  imageUrl: _posts[i].thumbnailUrl ?? _posts[i].mediaUrl!,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(color: AppColors.surfaceBorder),
                )
              : Container(color: AppColors.surfaceBorder),
        ),
      );
    } else {
      grid = MasonryGridView.count(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(bottom: bottom),
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        itemCount: _posts.length,
        itemBuilder: (_, i) => _DiscoverTile(post: _posts[i], tall: true, onTap: () => _openPost(i)),
      );
    }
    return Column(children: [
      if (filters != null) filters,
      Expanded(child: RefreshIndicator(onRefresh: _reload, color: AppColors.primary, child: grid)),
      if (_loadingMore)
        const Padding(
          padding: EdgeInsets.all(8),
          child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
        ),
    ]);
  }

  Widget _adFilters() => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: SizedBox(
          height: 30,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final e in [const MapEntry<String?, String>(null, 'All'), ...kAdCategories.entries])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(e.value, style: const TextStyle(fontSize: 11.5)),
                    selected: _adCategory == e.key,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) {
                      setState(() => _adCategory = e.key);
                      _reload();
                    },
                  ),
                ),
            ],
          ),
        ),
      );
}


/// A drama, movie or video in search results.
class _TitleResult extends StatelessWidget {
  final Post post;
  final VoidCallback onTap;
  const _TitleResult({required this.post, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final title = post.seriesTitle ?? (post.caption.trim().isEmpty ? 'Video' : post.caption.split('\n').first);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: post.thumbnailUrl != null
            ? SizedBox(
                width: 48,
                height: 64,
                child: RetryableNetworkImage(imageUrl: post.thumbnailUrl!, fit: BoxFit.cover,
                    placeholder: (_, __) => Container(color: AppColors.surfaceBorder)),
              )
            : Container(width: 48, height: 64, color: AppColors.surfaceBorder,
                child: const Icon(Icons.movie_outlined, color: AppColors.textMuted, size: 18)),
      ),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(
        [if (post.seriesId != null) 'Series', '@${post.authorUsername ?? ''}'].join(' · '),
        style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
      ),
    );
  }
}
