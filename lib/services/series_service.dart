import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import '../constants/supabase_constants.dart';
import '../models/insufficient_coins_exception.dart';
import '../models/post.dart';
import '../models/series.dart';
import '../models/series_analytics.dart';
import 'supabase_service.dart';
import 'video_metadata_service.dart';

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
    int coinPricePerEpisode = 30,
    String genre = kDefaultDramaGenre,
    // Sent conditionally, and retried without them below, so creating
    // a title still works before the content_type/orientation columns
    // are migrated — same pattern as PostService.createPost's Bunny
    // fields.
    String? contentType,
    String? orientation,
  }) async {
    final row = {
      'user_id': userId,
      'title': title,
      'description': description,
      'cover_image_url': coverImageUrl,
      'coin_price_per_episode': coinPricePerEpisode,
      'genre': genre,
    };
    final extraFields = {
      if (contentType != null) 'content_type': contentType,
      if (orientation != null) 'orientation': orientation,
    };

    Map<String, dynamic> inserted;
    try {
      inserted = await _client.from('series').insert({...row, ...extraFields}).select().single();
    } catch (e) {
      if (extraFields.isEmpty || !e.toString().contains('column')) rethrow;
      inserted = await _client.from('series').insert(row).select().single();
    }
    return Series.fromJson(inserted);
  }

  /// Owner-only status flip (Ongoing/Completed) — a direct RLS-scoped
  /// update rather than routed through the backend, unlike
  /// setCoverImage above: that one is usually called by a stranger
  /// (any viewer of a coverless series) and needs the backend's
  /// service-role client to get past `series`' owner-only update
  /// policy at all, while this is only ever invoked by the series'
  /// own owner (gated in the UI), for whom that same RLS policy
  /// already lets a direct client write through.
  static Future<void> updateStatus(String seriesId, String status) async {
    await _client.from('series').update({'status': status}).eq('id', seriesId);
  }

  /// True per-series follow (`series_follows`) — distinct from the
  /// creator-level `follows` table used elsewhere in the app. A viewer
  /// can follow a specific series without following everything else
  /// that creator makes, and vice versa. Phase 2 table — every method
  /// here fails silently/returns a safe default if it doesn't exist
  /// yet (the migration hasn't run), same "inert until migrated"
  /// posture as series.status in Phase 1.
  static Future<bool> isFollowingSeries(String userId, String seriesId) async {
    try {
      final row = await _client
          .from('series_follows')
          .select('id')
          .eq('follower_id', userId)
          .eq('series_id', seriesId)
          .maybeSingle();
      return row != null;
    } catch (_) {
      return false;
    }
  }

  static Future<void> followSeries(String userId, String seriesId) async {
    await _client.from('series_follows').insert({
      'follower_id': userId,
      'series_id': seriesId,
    });
  }

  static Future<void> unfollowSeries(String userId, String seriesId) async {
    await _client
        .from('series_follows')
        .delete()
        .eq('follower_id', userId)
        .eq('series_id', seriesId);
  }

  static Future<int> getSeriesFollowerCount(String seriesId) async {
    try {
      final res = await _client
          .from('series_follows')
          .select('id')
          .eq('series_id', seriesId)
          .count();
      return res.count;
    } catch (_) {
      return 0;
    }
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

  /// Fires the new-episode fan-out to the creator's followers — see
  /// episode_notify.py. Fire-and-forget, same posture as setCoverImage
  /// above: a dropped notification must never surface as an upload
  /// failure to the creator who's actually waiting on the real result.
  static Future<void> notifyNewEpisode(String postId) async {
    try {
      final token = _client.auth.currentSession?.accessToken;
      await http.post(
        Uri.parse('${AiBackendConstants.baseUrl}/api/v1/episodes/$postId/notify-followers'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      );
    } catch (_) {}
  }

  // Series ids already backfilled (or attempted and failed) this app
  // session — a plain in-memory guard against every concurrent screen
  // that lists series (Dramas tab, Discover) kicking off its own
  // duplicate capture-and-upload for the same series.
  static final _backfillAttempted = <String>{};

  /// Self-heals a series with no cover image by grabbing one from its
  /// earliest episode. Fire-and-forget: called from getAllSeries/
  /// getNewAiSeries below without awaiting, so a slow or failed
  /// backfill never delays the list those screens are actually
  /// waiting on. Runs on every platform now — generation moved
  /// server-side (see VideoMetadataService.generateThumbnail /
  /// viyo_ai's video_metadata.py), so it no longer depends on a
  /// browser's <video>/<canvas> being available or able to capture a
  /// cross-origin frame without hitting a tainted-canvas error.
  static void backfillCoverIfMissing(Series series) {
    if (series.coverImageUrl != null) return;
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

      // Cheapest path: the episode already has its own thumbnail — just
      // point the series at it, no generation needed.
      final existingThumb = row['thumbnail_url'] as String?;
      if (existingThumb != null) {
        await setCoverImage(series.id, existingThumb);
        return;
      }

      final mediaUrl = row['media_url'] as String?;
      if (mediaUrl == null) return;

      final generatedUrl = await VideoMetadataService.generateThumbnail(mediaUrl: mediaUrl);
      if (generatedUrl == null) return;
      await setCoverImage(series.id, generatedUrl);
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
  /// [includePrivate] surfaces a not-yet-published scheduled episode
  /// (see ScheduledReleaseService) — only ever passed true by the
  /// series' own owner reviewing their own upcoming releases. Every
  /// other caller (a stranger browsing the series, VideoFeedScreen's
  /// own playlist for a series) leaves this false, so a scheduled
  /// episode is neither listed nor playable before its time.
  static Future<List<Post>> getSeriesEpisodes(String seriesId, {bool includePrivate = false}) async {
    var query = _client
        .from('posts')
        .select('*, profiles(username, display_name, avatar_url), series(title, coin_price_per_episode, orientation)')
        .eq('series_id', seriesId);
    if (!includePrivate) {
      query = query.eq('is_private', false);
    }
    final data = await query.order('episode_number', ascending: true);

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
  /// pattern as PostService._withLikedByMe. An active Viyo Premium
  /// subscriber gets unlockedByMe=true on every episode regardless of
  /// episode_unlocks, which is the only place this needs to be
  /// checked — isEpisodeLocked and every screen that calls it
  /// (video_feed_screen, series_detail_screen, post_card) already key
  /// off unlockedByMe alone, so nothing downstream needs to know
  /// subscriptions exist.
  static Future<List<Post>> _withUnlockState(List<Post> episodes) async {
    final userId = SupabaseService.currentUserId;
    if (userId == null || episodes.isEmpty) return episodes;
    try {
      final profileRow = await _client
          .from('profiles')
          .select('is_subscribed')
          .eq('id', userId)
          .maybeSingle();
      if (profileRow != null && profileRow['is_subscribed'] == true) {
        return episodes.map((e) => e.copyWith(unlockedByMe: true)).toList();
      }

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
        .select('*, profiles(username, display_name, avatar_url), series(title, coin_price_per_episode, orientation)')
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
  // A series-level boost (see SeriesBoostService/series_boost.py) is a
  // bigger, pricier commitment than a single episode's own is_boosted
  // flag below — it lifts the whole series' aggregate score, not one
  // episode's contribution to it, so it gets a stronger multiplier.
  static const double _seriesBoostMultiplier = 5.0;

  static Future<List<Series>> getAllSeries({
    String? genre,
    // One of series.dart's kContentType* ids, or null for "every type"
    // (the default — unchanged behavior). Filtered client-side rather
    // than via `.eq('content_type', ...)`: content_type is null for
    // every series made before that column existed, and those are all
    // Short Drama — a plain equality filter can't express "this value,
    // or null" without excluding them, but Series.effectiveContentType
    // already encodes exactly that fallback.
    String? contentType,
    DramaSort sort = DramaSort.newest,
    int limit = 60,
    Set<String> boostedSeriesIds = const {},
  }) async {
    var query = _client.from('series').select('*, profiles(username, display_name, avatar_url)');
    if (genre != null && genre.isNotEmpty) {
      query = query.eq('genre', genre);
    }
    // A wider pool than `limit` when ranking by engagement — the
    // newest-first order below isn't the final order in that case, so
    // narrowing to exactly `limit` rows first would silently exclude an
    // older-but-popular series from ever being scored at all. Wider
    // again when filtering by content type, since that filter only
    // happens after this fetch (see above) — same "rank/filter a
    // bounded pool client-side" tradeoff the rest of this method
    // already makes, just one dimension wider.
    var poolSize = sort == DramaSort.newest ? limit : limit * 4;
    if (contentType != null) poolSize *= 3;
    final data = await query.order('created_at', ascending: false).limit(poolSize);
    var series = (data as List).map((e) => Series.fromJson(e)).toList();
    if (contentType != null) {
      series = series.where((s) => s.effectiveContentType == contentType).toList();
    }
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

    if (boostedSeriesIds.isNotEmpty) {
      for (final sid in scores.keys.toList()) {
        if (boostedSeriesIds.contains(sid)) scores[sid] = scores[sid]! * _seriesBoostMultiplier;
      }
    }

    series.sort((a, b) => (scores[b.id] ?? 0).compareTo(scores[a.id] ?? 0));
    return series.take(limit).toList();
  }

  /// Which of three honest, simple labels each already-ranked series
  /// (from getAllSeries(sort: hot)) earns — a separate, additive query
  /// rather than touching getAllSeries' own ranking logic. Per the
  /// product spec: show a transparent-feeling label, never the actual
  /// score. Best-effort — an empty map just means no series gets a
  /// badge, never an error the Trending row would have to handle.
  static Future<Map<String, String>> getTrendingLabels(List<Series> trendingSeries) async {
    if (trendingSeries.isEmpty) return {};
    try {
      final seriesIds = trendingSeries.map((s) => s.id).toList();
      final episodeRows = await _client
          .from('posts')
          .select('series_id, like_count, comment_count, view_count, created_at')
          .inFilter('series_id', seriesIds);

      final now = DateTime.now();
      final scores = <String, double>{};
      final firstPublished = <String, DateTime>{};
      for (final row in (episodeRows as List)) {
        final sid = row['series_id'] as String?;
        if (sid == null) continue;
        final likes = (row['like_count'] as num?)?.toInt() ?? 0;
        final comments = (row['comment_count'] as num?)?.toInt() ?? 0;
        final views = (row['view_count'] as num?)?.toInt() ?? 0;
        scores[sid] = (scores[sid] ?? 0) + likes + comments * 2 + views ~/ 10;

        final createdAt = DateTime.tryParse(row['created_at'] as String? ?? '');
        if (createdAt != null) {
          final existing = firstPublished[sid];
          if (existing == null || createdAt.isBefore(existing)) {
            firstPublished[sid] = createdAt;
          }
        }
      }
      if (scores.isEmpty) return {};

      // "High for this pool" — the top 30% of trending-row scores —
      // rather than a fixed number, so the bar scales with however
      // engaged this app's own trending pool currently is.
      final sortedScores = scores.values.toList()..sort();
      final topThreshold = sortedScores[(sortedScores.length * 0.7).floor().clamp(0, sortedScores.length - 1)];

      final labels = <String, String>{};
      for (final s in trendingSeries) {
        final firstEp = firstPublished[s.id];
        final ageDays = firstEp == null ? 999.0 : now.difference(firstEp).inHours / 24.0;
        final score = scores[s.id] ?? 0;
        if (ageDays <= 7) {
          labels[s.id] = 'NEW & POPULAR';
        } else if (ageDays <= 30 && score >= topThreshold) {
          labels[s.id] = 'RISING FAST';
        } else {
          labels[s.id] = 'TRENDING NOW';
        }
      }
      return labels;
    } catch (_) {
      return {};
    }
  }

  /// "Because You Watched" — a lightweight, non-ML recommendation: the
  /// same genre as one series the viewer's actually watched, hottest
  /// first, excluding that series itself. Deliberately not a real
  /// recommender (no collaborative filtering, no embeddings) — genre
  /// match off real watch history beats a generic trending re-list, and
  /// costs nothing new to build. Best-effort: an unresolvable source
  /// series (e.g. since deleted) just means the row doesn't show.
  static Future<List<Series>> getBecauseYouWatched(String sourceSeriesId, {int limit = 12}) async {
    try {
      final source = await getSeries(sourceSeriesId);
      if (source == null) return [];
      final results = await getAllSeries(genre: source.genre, sort: DramaSort.hot, limit: limit + 1);
      return results.where((s) => s.id != sourceSeriesId).take(limit).toList();
    } catch (_) {
      return [];
    }
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

    throw _errorFor(res, 'Could not unlock episode');
  }

  /// Builds the exception to throw for a non-200 unlock response — an
  /// InsufficientCoinsException on a 402 from episodes.py's debit_coins,
  /// same shape ai_service.dart already uses for coin-gated AI features,
  /// so this reaches the same "watch an ad / buy coins" sheet instead of
  /// a flat error snackbar. A plain Exception with the server's own
  /// detail message otherwise.
  static Exception _errorFor(http.Response res, String fallback) {
    try {
      final data = jsonDecode(res.body);
      final detail = data is Map ? data['detail'] : null;
      if (res.statusCode == 402 && detail is Map && detail['error'] == 'insufficient_coins') {
        return InsufficientCoinsException(
          feature: 'this episode',
          balance: (detail['balance'] as num?)?.toInt() ?? 0,
          needed: (detail['needed'] as num?)?.toInt() ?? 0,
        );
      }
      if (detail is String) return Exception(detail);
    } catch (_) {}
    return Exception('$fallback (${res.statusCode})');
  }

  /// Unlocks every currently-locked episode of a series in one purchase
  /// at a discount (see episodes.py's unlock_series_bundle) — not just
  /// N calls to unlockEpisode, which can't apply a discount and would
  /// multiply that endpoint's own partial-failure surface by N. Returns
  /// the raw response map (unlocked_episode_ids, coins_spent,
  /// already_complete) rather than a typed model since the only caller
  /// needs just the id list to flip local state.
  static Future<Map<String, dynamic>> unlockSeriesBundle(String seriesId) async {
    final token = _client.auth.currentSession?.accessToken;
    final res = await http.post(
      Uri.parse('${AiBackendConstants.baseUrl}/api/v1/series/$seriesId/unlock-bundle'),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
    );
    if (res.statusCode == 200) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }

    String? message;
    try {
      final data = jsonDecode(res.body);
      final detail = data is Map ? data['detail'] : null;
      message = detail is String
          ? detail
          : (detail is Map ? detail['error']?.toString() : null);
    } catch (_) {}
    throw Exception(message ?? 'Could not unlock series (${res.statusCode})');
  }

  /// Owner-only — the backend itself enforces this (403s otherwise),
  /// this is just the client-side call. Routed through the backend
  /// rather than a direct client read because the aggregation
  /// (completion rate/drop-off from watch_progress) happens in Python,
  /// not something PostgREST can compute on its own.
  static Future<SeriesAnalytics> getSeriesAnalytics(String seriesId) async {
    final token = _client.auth.currentSession?.accessToken;
    final res = await http.get(
      Uri.parse('${AiBackendConstants.baseUrl}/api/v1/series/$seriesId/analytics'),
      headers: {if (token != null) 'Authorization': 'Bearer $token'},
    );
    if (res.statusCode == 200) {
      return SeriesAnalytics.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
    }

    String? message;
    try {
      final data = jsonDecode(res.body);
      message = data is Map ? data['detail']?.toString() : null;
    } catch (_) {}
    throw Exception(message ?? 'Could not load analytics (${res.statusCode})');
  }
}
