import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants/supabase_constants.dart';
import '../models/post.dart';
import '../models/series.dart';
import 'moderation_service.dart';
import 'post_service.dart';
import 'promotion_service.dart';
import 'series_service.dart';
import 'supabase_service.dart';

/// Discover's categories. Each one reads existing records (posts and series), never a copy of them.
enum DiscoverCategory { forYou, shorts, movies, dramas, ads, photos }

extension DiscoverCategoryLabel on DiscoverCategory {
  String get label => switch (this) {
        DiscoverCategory.forYou => 'For You',
        DiscoverCategory.shorts => 'Shorts',
        DiscoverCategory.movies => 'Movies',
        DiscoverCategory.dramas => 'Dramas',
        DiscoverCategory.ads => 'Ads',
        DiscoverCategory.photos => 'Photos',
      };

  bool get isSeries => this == DiscoverCategory.movies || this == DiscoverCategory.dramas;
}

/// Categories an ad can be published under (same keys as viyo_ai's ads_publish.AD_CATEGORIES).
const kAdCategories = <String, String>{
  'food_drink': 'Food & drink',
  'fashion_beauty': 'Fashion & beauty',
  'apps_tech': 'Apps & tech',
  'home_living': 'Home & living',
  'services': 'Services',
  'entertainment': 'Film, music & events',
  'education': 'Education',
  'health_fitness': 'Health & fitness',
  'travel_places': 'Travel & places',
  'business': 'Business',
  'other': 'Other',
};

class DiscoverService {
  static final _client = SupabaseService.client;
  static const pageSize = 24;
  static const shortMaxSeconds = 180;
  static const movieTypes = {kContentTypeMovie, kContentTypeShortFilm, kContentTypeAiFilm};
  static const dramaTypes = {kContentTypeShortDrama, kContentTypeSeries};

  /// One page (newest first) of Shorts, Ads or Photos. [offset] counts rows already loaded.
  static Future<List<Post>> posts(DiscoverCategory category, {int offset = 0, String? adCategory}) async {
    assert(!category.isSeries && category != DiscoverCategory.forYou);
    List data;
    try {
      data = await _query(category, offset, adCategory, withKind: true);
    } catch (e) {
      // Before ads_publish.sql has run there is no post_kind column: there are no ads yet, and every post
      // is an ordinary one.
      if (!e.toString().contains('post_kind') && !e.toString().contains('ad_category')) rethrow;
      if (category == DiscoverCategory.ads) return [];
      data = await _query(category, offset, null, withKind: false);
    }
    var posts = data.map((e) => Post.fromJson(e as Map<String, dynamic>)).toList();
    if (category == DiscoverCategory.shorts) {
      posts = posts.where((p) => (p.durationSeconds ?? 0) <= shortMaxSeconds && !p.isLandscapeVideo).toList();
    }
    final me = SupabaseService.currentUserId;
    if (me != null) {
      final hidden = await ModerationService.getHiddenUserIds(me);
      if (hidden.isNotEmpty) posts = posts.where((p) => !hidden.contains(p.userId)).toList();
    }
    return PostService.withLikedByMe(posts);
  }

  static Future<List> _query(DiscoverCategory category, int offset, String? adCategory, {required bool withKind}) {
    var q = _client
        .from('posts')
        .select('*, profiles(username, display_name, avatar_url)')
        .eq('is_private', false)
        .eq('is_archived', false)
        .not('media_url', 'is', null);
    switch (category) {
      case DiscoverCategory.shorts:
        q = q.eq('post_type', 'video').isFilter('series_id', null);
        if (withKind) q = q.eq('post_kind', 'post');
      case DiscoverCategory.ads:
        q = q.eq('post_kind', 'ad');
        if (adCategory != null) q = q.eq('ad_category', adCategory);
      case DiscoverCategory.photos:
        q = q.eq('post_type', 'photo');
      default:
        break;
    }
    return q.order('created_at', ascending: false).range(offset, offset + pageSize - 1);
  }

  /// Movies or Dramas: series with at least one public episode, with their own poster and series page.
  static Future<List<Series>> series(DiscoverCategory category, {int limit = pageSize}) =>
      SeriesService.getAllSeries(
        contentTypes: category == DiscoverCategory.movies ? movieTypes : dramaTypes,
        sort: DramaSort.hot,
        limit: limit,
      );

  /// For You keeps ads a small part of what you see: never in the first [firstAt] tiles, at least [every]
  /// tiles apart, and the rest of the ads are left for the Ads category. Ordinary posts keep their order.
  static List<Post> capAds(List<Post> ranked, {int every = 6, int firstAt = 3}) {
    final ordinary = ranked.where((p) => !p.isAd).toList();
    final ads = ranked.where((p) => p.isAd).toList();
    final out = <Post>[];
    var sinceAd = every - firstAt; // so the first ad can land at index [firstAt] at the earliest
    var oi = 0, ai = 0;
    while (oi < ordinary.length) {
      if (ai < ads.length && sinceAd >= every && out.length >= firstAt) {
        out.add(ads[ai++]);
        sinceAd = 0;
      } else {
        out.add(ordinary[oi++]);
        sinceAd++;
      }
    }
    return out;
  }

  /// Adds up to two paid promotions (labelled "Promoted") for this placement: For You at the 5th and 12th
  /// places, the Ads category first. A promoted post replaces its own unpaid copy, never shows twice.
  /// On any error the list comes back unchanged.
  static Future<List<Post>> withPromotions(List<Post> posts, String placement, {String? adCategory}) async {
    final picks = await PromotionService.serve(placement);
    if (picks.isEmpty) return posts;
    List<Post> promoted;
    try {
      final byId = {for (final p in await PostService.getPostsByIds([for (final x in picks) x.postId])) p.id: p};
      final me = SupabaseService.currentUserId;
      final hidden = me == null ? <String>{} : await ModerationService.getHiddenUserIds(me);
      promoted = [
        for (final x in picks)
          if (byId[x.postId] != null &&
              byId[x.postId]!.isAd &&
              !byId[x.postId]!.isPrivate &&
              !byId[x.postId]!.isArchived &&
              !hidden.contains(byId[x.postId]!.userId) &&
              (adCategory == null || byId[x.postId]!.adCategory == adCategory))
            byId[x.postId]!.copyWith(promotionId: x.promotionId),
      ];
    } catch (_) {
      return posts;
    }
    if (promoted.isEmpty) return posts;
    final ids = promoted.map((p) => p.id).toSet();
    final out = posts.where((p) => !ids.contains(p.id)).toList();
    if (placement == 'ads') return [...promoted, ...out];
    for (var i = 0; i < promoted.length; i++) {
      out.insert((i == 0 ? 4 : 11).clamp(0, out.length), promoted[i]);
    }
    return out;
  }
}

/// Trending, fast-growing, new releases and rising creators from the server (trending.py).
class TrendingSections {
  final List<Post> trending, fastGrowing, newReleases, risingCreators;
  final List<String> genres;
  TrendingSections(this.trending, this.fastGrowing, this.newReleases, this.risingCreators, this.genres);
}

/// One search result row: a title (drama/movie/short film/video) or a creator.
class SearchResults {
  final List<Post> titles;          // each the post to open (a series' first/next episode)
  final List<Map<String, dynamic>> creators;
  final List<String> understoodGenres;
  SearchResults(this.titles, this.creators, this.understoodGenres);
}

class ServerDiscovery {
  static Map<String, String> get _headers {
    final token = SupabaseService.client.auth.currentSession?.accessToken;
    return {if (token != null) 'Authorization': 'Bearer $token'};
  }

  static Future<List<Post>> _posts(List ids) async {
    final list = [for (final i in ids) (i as Map)['post_id'].toString()];
    if (list.isEmpty) return [];
    final byId = {for (final p in await PostService.getPostsByIds(list)) p.id: p};
    return [for (final id in list) if (byId[id] != null) byId[id]!];
  }

  /// Null when the server can't be reached (callers keep their existing sections).
  static Future<TrendingSections?> trending() async {
    try {
      final res = await http
          .get(Uri.parse('${AiBackendConstants.baseUrl}/api/v1/discover/trending'), headers: _headers)
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      return TrendingSections(
        await _posts(j['trending'] as List? ?? const []),
        await _posts(j['fast_growing'] as List? ?? const []),
        await _posts(j['new_releases'] as List? ?? const []),
        await _posts(j['rising_creators'] as List? ?? const []),
        [for (final g in (j['genres'] as List? ?? const [])) (g as Map)['genre'].toString()],
      );
    } catch (_) {
      return null;
    }
  }

  /// Titles and creators matching [query] (partial words, typos, or a described story). Null on failure.
  static Future<SearchResults?> search(String query) async {
    try {
      final res = await http
          .get(Uri.parse('${AiBackendConstants.baseUrl}/api/v1/search?q=${Uri.encodeQueryComponent(query)}'),
              headers: _headers)
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      return SearchResults(
        await _posts(j['results'] as List? ?? const []),
        [for (final c in (j['creators'] as List? ?? const [])) Map<String, dynamic>.from(c as Map)],
        [for (final g in (j['understood_genres'] as List? ?? const [])) g.toString()],
      );
    } catch (_) {
      return null;
    }
  }
}
