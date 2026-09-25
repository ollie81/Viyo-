import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import '../constants/supabase_constants.dart';
import '../models/post.dart';
import '../models/series.dart';
import 'post_service.dart';
import 'supabase_service.dart';
import 'web_thumbnail_stub.dart' if (dart.library.html) 'web_thumbnail_html.dart' as web_thumbnail;

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
  ///
  /// Routed through the backend rather than a direct Supabase update:
  /// `series`' RLS update policy is owner-only, but this is called from
  /// every viewer who sees a coverless series — overwhelmingly a
  /// stranger browsing someone else's series in Discover/the Dramas
  /// tab, not the owner — so a direct client write silently no-ops for
  /// almost every caller. The backend's service-role client can write
  /// regardless of who's viewing, with its own narrower checks (only
  /// fills a null cover, only accepts this series' own episode
  /// thumbnail or a Viyo-hosted upload) standing in for the RLS check
  /// this bypasses.
  static Future<void> setCoverImage(String seriesId, String coverImageUrl) async {
    try {
      final token = _client.auth.currentSession?.accessToken;
      await http.post(
        Uri.parse('${AiBackendConstants.baseUrl}/api/v1/series/$seriesId/cover'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'cover_image_url': coverImageUrl}),
      );
    } catch (_) {}
  }

  // Series ids already backfilled (or attempted and failed) this app
  // session — a plain in-memory guard against every concurrent screen
  // that lists series (Dramas tab, Discover) kicking off its own
  // duplicate capture-and-upload for the same series.
  static final _backfillAttempted = <String>{};

  /// Self-heals a series with no cover image by grabbing one from its
  /// earliest episode — for every series created before web thumbnail
  /// capture existed (see post_service.dart's generateAndUploadVideo
  /// Thumbnail), whose episodes also have no thumbnail of their own,
  /// so there's nothing to just copy over. Fire-and-forget: called
  /// from getAllSeries/getNewAiSeries below without awaiting, so a slow
  /// or failed backfill never delays the list those screens are
  /// actually waiting on. Web-only — the capture technique itself
  /// needs a browser's <video>/<canvas>; a series uploaded from the
  /// native app already has a real thumbnail from video_thumbnail, so
  /// there's nothing to backfill there anyway.
  static void backfillCoverIfMissing(Series series) {
    if (!kIsWeb || series.coverImageUrl != null) return;
    if (!_backfillAttempted.add(series.id)) return;
    unawaited(_doBackfillCover(series));
  }

  static Future<void> _doBackfillCover(Series series) async {
    try {
      final row = await _client
          .from('posts')
          .select('media_url, thumbnail_url')
          .eq('series_id', series.id)
          .order('episode_number', ascending: true)
          .limit(1)
          .maybeSingle();
      if (row == null) return;

      // Cheapest path: the episode already has its own thumbnail
      // (e.g. uploaded from the native app, or by a future fixed web
      // build) — just point the series at it, no capture needed.
      final existingThumb = row['thumbnail_url'] as String?;
      if (existingThumb != null) {
        await setCoverImage(series.id, existingThumb);
        return;
      }

      final mediaUrl = row['media_url'] as String?;
      if (mediaUrl == null) return;

      final jpegBytes = await web_thumbnail.captureVideoFrameFromUrlWeb(mediaUrl);
      if (jpegBytes == null) return;

      final userId = SupabaseService.currentUserId;
      if (userId == null) return;
      final thumbFile = XFile.fromData(jpegBytes, name: 'thumbnail.jpg', mimeType: 'image/jpeg');
      final uploadedUrl = await PostService.uploadMediaWithProgress(thumbFile, userId);
      await setCoverImage(series.id, uploadedUrl);
    } catch (_) {
      // Best-effort — a failed backfill just leaves the placeholder
      // tile in place, same as a series with no episodes yet.
    }
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

    final result = seriesList.map((s) => s.copyWith(episodeCount: counts[s.id] ?? 0)).toList();
    // The most reliable backfill trigger of the three call sites: this
    // is almost always the owner looking at their own series (profile's
    // Series tab, the upload screen's series picker), so RLS actually
    // lets setCoverImage's update through here.
    for (final s in result) {
      backfillCoverIfMissing(s);
    }
    return result;
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

  // A creator's paid boost (PostBoostService.boostPost) — same
  // multiplier PostService uses for the home feed/Discover post grid,
  // so a boosted episode gets the same lift here instead of the coin
  // spend doing nothing for drama-specific ranking.
  static const double _boostMultiplier = 4.0;

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
      final raw = engagement <= 0 ? 1 / (ageHours + 1) : engagement / (ageHours + 2);
      return p.isBoosted ? raw * _boostMultiplier : raw;
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
    final series = (data as List).map((e) => Series.fromJson(e)).toList();
    for (final s in series) {
      backfillCoverIfMissing(s);
    }
    return series;
  }

  /// Every public series, optionally narrowed to one genre and ordered
  /// by [sort] — powers the Dramas tab's poster grid. Popular/hot both
  /// need per-series engagement, which lives on episodes (posts), not
  /// the series row itself, so those two pull every matching series'
  /// episodes in one extra query and aggregate client-side — the same
  /// "rank a bounded pool client-side" tradeoff PostService.getFeed
  /// already makes, just one level up (series instead of posts).
  static Future<List<Series>> getAllSeries({
    String? genre,
    DramaSort sort = DramaSort.newest,
    int limit = 60,
  }) async {
    var query = _client.from('series').select('*, profiles(username, display_name, avatar_url)');
    if (genre != null && genre.isNotEmpty) {
      query = query.eq('genre', genre);
    }
    // A wider pool than `limit` when ranking by engagement — the
    // newest-first order below isn't the final order in that case, so
    // narrowing to exactly `limit` rows first would silently exclude an
    // older-but-popular series from ever being scored at all.
    final poolSize = sort == DramaSort.newest ? limit : limit * 4;
    final data = await query.order('created_at', ascending: false).limit(poolSize);
    final series = (data as List).map((e) => Series.fromJson(e)).toList();
    for (final s in series) {
      backfillCoverIfMissing(s);
    }
    if (series.isEmpty || sort == DramaSort.newest) {
      return series.take(limit).toList();
    }

    final seriesIds = series.map((s) => s.id).toList();
    final episodeRows = await _client
        .from('posts')
        .select('series_id, like_count, comment_count, view_count, created_at, is_boosted')
        .inFilter('series_id', seriesIds);

    final scores = <String, double>{};
    final now = DateTime.now();
    for (final row in (episodeRows as List)) {
      final sid = row['series_id'] as String?;
      if (sid == null) continue;
      final likes = (row['like_count'] as num?)?.toInt() ?? 0;
      final comments = (row['comment_count'] as num?)?.toInt() ?? 0;
      final views = (row['view_count'] as num?)?.toInt() ?? 0;
      final engagement = likes + comments * 2 + views ~/ 10;

      double contribution;
      if (sort == DramaSort.hot) {
        final createdAt = DateTime.tryParse(row['created_at'] as String? ?? '') ?? now;
        final ageHours = now.difference(createdAt).inMinutes / 60.0;
        contribution = engagement / pow(ageHours + 2, 1.2);
      } else {
        contribution = engagement.toDouble();
      }
      // A boosted episode lifts its whole series' score, not just that
      // one episode's own standing — the same "coins spent" signal the
      // home feed/Discover already honor, now meaningful here too.
      if (row['is_boosted'] == true) contribution *= _boostMultiplier;
      scores[sid] = (scores[sid] ?? 0) + contribution;
    }

    series.sort((a, b) => (scores[b.id] ?? 0).compareTo(scores[a.id] ?? 0));
    return series.take(limit).toList();
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
