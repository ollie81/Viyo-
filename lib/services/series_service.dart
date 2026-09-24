import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants/supabase_constants.dart';
import '../models/post.dart';
import '../models/series.dart';
import 'supabase_service.dart';

/// AI Short Drama series: creating/listing a series and its episodes is
/// a direct Supabase read/write (RLS scopes writes to your own rows,
/// same as posts) — only the actual coin-spending unlock goes through
/// the Python backend, the same "backend only for cross-user money
/// movement" line drawn everywhere else in this app.
class SeriesService {
  static final _client = SupabaseService.client;

  static Future<Series> createSeries({
    required String userId,
    required String title,
    String description = '',
    String? coverImageUrl,
    int coinPricePerEpisode = 20,
    String genre = kDefaultDramaGenre,
  }) async {
    final inserted = await _client
        .from('series')
        .insert({
          'user_id': userId,
          'title': title,
          'description': description,
          'cover_image_url': coverImageUrl,
          'coin_price_per_episode': coinPricePerEpisode,
          'genre': genre,
        })
        .select()
        .single();
    return Series.fromJson(inserted);
  }

  /// Backfills a series' poster art from its first episode's thumbnail
  /// — called right after a new series' first episode finishes
  /// uploading, since the create-series step above happens before any
  /// video/thumbnail exists yet. Best-effort: a series with no cover
  /// just falls back to a placeholder tile, never blocks publishing.
  static Future<void> setCoverImage(String seriesId, String coverImageUrl) async {
    try {
      await _client.from('series').update({'cover_image_url': coverImageUrl}).eq('id', seriesId);
    } catch (_) {}
  }

  /// A creator's own series, each stamped with its real episode count —
  /// one query for the series rows, one for every episode's series_id
  /// so the count is computed here rather than trusting a stored
  /// counter column that could drift.
  static Future<List<Series>> getUserSeries(String userId) async {
    final seriesData = await _client
        .from('series')
        .select('*, profiles(username, display_name, avatar_url)')
        .eq('user_id', userId)
        .order('created_at', ascending: false);

    final seriesList = (seriesData as List).map((e) => Series.fromJson(e)).toList();
    if (seriesList.isEmpty) return seriesList;

    final episodeRows = await _client
        .from('posts')
        .select('series_id')
        .eq('user_id', userId)
        .not('series_id', 'is', null);

    final counts = <String, int>{};
    for (final row in (episodeRows as List)) {
      final sid = row['series_id'] as String?;
      if (sid == null) continue;
      counts[sid] = (counts[sid] ?? 0) + 1;
    }

    return seriesList.map((s) => s.copyWith(episodeCount: counts[s.id] ?? 0)).toList();
  }

  static Future<Series?> getSeries(String seriesId) async {
    final data = await _client
        .from('series')
        .select('*, profiles(username, display_name, avatar_url)')
        .eq('id', seriesId)
        .maybeSingle();
    if (data == null) return null;
    return Series.fromJson(data);
  }

  /// A series' episodes in watch order, each stamped with whether the
  /// current viewer has unlocked it. The owner never needs an unlock
  /// row — episode_unlocks would never contain one for their own
  /// content, so unlockedByMe alone can't distinguish "the owner" from
  /// "a stranger who hasn't paid"; callers check post.userId separately
  /// (see EpisodeLock.isLockedFor in episode_lock.dart).
  static Future<List<Post>> getSeriesEpisodes(String seriesId) async {
    final data = await _client
        .from('posts')
        .select('*, profiles(username, display_name, avatar_url), series(title, coin_price_per_episode)')
        .eq('series_id', seriesId)
        .order('episode_number', ascending: true);

    final episodes = (data as List).map((e) => Post.fromJson(e)).toList();
    return _withUnlockState(episodes);
  }

  static Future<int> getNextEpisodeNumber(String seriesId) async {
    final data = await _client
        .from('posts')
        .select('episode_number')
        .eq('series_id', seriesId)
        .order('episode_number', ascending: false)
        .limit(1);
    final rows = data as List;
    if (rows.isEmpty) return 1;
    return ((rows.first['episode_number'] as num?)?.toInt() ?? 0) + 1;
  }

  /// Stamps unlockedByMe from a direct episode_unlocks read (RLS
  /// restricts this to the caller's own rows) — same "read your own
  /// state directly, don't round-trip through the backend for it"
  /// pattern as PostService._withLikedByMe.
  static Future<List<Post>> _withUnlockState(List<Post> episodes) async {
    final userId = SupabaseService.currentUserId;
    if (userId == null || episodes.isEmpty) return episodes;
    try {
      final unlocked = await _client
          .from('episode_unlocks')
          .select('post_id')
          .eq('user_id', userId)
          .inFilter('post_id', episodes.map((e) => e.id).toList());
      final unlockedIds = (unlocked as List).map((r) => r['post_id'] as String).toSet();
      return episodes.map((e) => e.copyWith(unlockedByMe: unlockedIds.contains(e.id))).toList();
    } catch (_) {
      return episodes;
    }
  }

  /// Discover's "Trending AI Dramas" — the same hot-ranked pool as the
  /// rest of Discover (see PostService.getDiscoverPosts), just narrowed
  /// to episodes (series_id set at all).
  static Future<List<Post>> getTrendingAiDramas({int limit = 20}) async {
    final data = await _client
        .from('posts')
        .select('*, profiles(username, display_name, avatar_url), series(title, coin_price_per_episode)')
        .eq('is_private', false)
        .eq('is_archived', false)
        .not('series_id', 'is', null)
        .order('created_at', ascending: false)
        .limit(100);
    final posts = (data as List).map((e) => Post.fromJson(e)).toList();

    double score(Post p) {
      final ageHours = DateTime.now().difference(p.createdAt).inMinutes / 60.0;
      final engagement = p.likeCount + p.commentCount * 2 + p.viewCount ~/ 10;
      if (engagement <= 0) return 1 / (ageHours + 1);
      return engagement / (ageHours + 2);
    }

    posts.sort((a, b) => score(b).compareTo(score(a)));
    return posts.take(limit).toList();
  }

  /// Discover's "New AI Series" — freshly started series, newest first.
  static Future<List<Series>> getNewAiSeries({int limit = 12}) async {
    final data = await _client
        .from('series')
        .select('*, profiles(username, display_name, avatar_url)')
        .order('created_at', ascending: false)
        .limit(limit);
    return (data as List).map((e) => Series.fromJson(e)).toList();
  }

  /// Every public series, optionally narrowed to one genre — powers the
  /// Dramas tab's poster grid. Newest-first: with no per-series
  /// engagement metric to rank by (that lives on episodes, not the
  /// series row itself), recency is the honest signal, same call
  /// getNewAiSeries above already makes.
  static Future<List<Series>> getAllSeries({String? genre, int limit = 60}) async {
    var query = _client.from('series').select('*, profiles(username, display_name, avatar_url)');
    if (genre != null && genre.isNotEmpty) {
      query = query.eq('genre', genre);
    }
    final data = await query.order('created_at', ascending: false).limit(limit);
    return (data as List).map((e) => Series.fromJson(e)).toList();
  }

  /// Spends coins to unlock a locked episode — routed through the
  /// backend's service-role client since it both debits the viewer and
  /// credits a *different* user's earnings balance, the same
  /// cross-user-money-movement rule as gifting/boost_post.
  static Future<int> unlockEpisode(String postId) async {
    final token = _client.auth.currentSession?.accessToken;
    final res = await http.post(
      Uri.parse('${AiBackendConstants.baseUrl}/api/v1/episodes/$postId/unlock'),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
    );
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return (data['coins_spent'] as num).toInt();
    }

    String? message;
    try {
      final data = jsonDecode(res.body);
      final detail = data is Map ? data['detail'] : null;
      message = detail is String
          ? detail
          : (detail is Map ? detail['error']?.toString() : null);
    } catch (_) {}
    throw Exception(message ?? 'Could not unlock episode (${res.statusCode})');
  }
}
