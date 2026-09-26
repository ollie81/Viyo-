import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/post.dart';
import 'post_service.dart';
import 'supabase_service.dart';

/// Per-device "where did I leave off" tracking, now layered with an
/// optional cross-device sync on top (Phase 2's `watch_progress`
/// table). The local SharedPreferences write stays the fast path every
/// call site already relies on; the server write is throttled far more
/// coarsely (see _serverSyncInterval) and fails silently if the table
/// doesn't exist yet — same "inert until migrated" posture as
/// series_follows/watchlist. This keeps every existing call site
/// (video_feed_screen.dart, series_detail_screen.dart) unchanged;
/// only the body here grew a second, best-effort destination.
class WatchProgressEntry {
  final String postId;
  final String seriesId;
  final String seriesTitle;
  final String? thumbnailUrl;
  final int episodeNumber;
  final int positionMs;
  final int durationMs;
  final DateTime updatedAt;

  const WatchProgressEntry({
    required this.postId,
    required this.seriesId,
    required this.seriesTitle,
    this.thumbnailUrl,
    required this.episodeNumber,
    required this.positionMs,
    required this.durationMs,
    required this.updatedAt,
  });

  double get fraction => durationMs <= 0 ? 0 : (positionMs / durationMs).clamp(0.0, 1.0);

  Map<String, dynamic> toJson() => {
        'postId': postId,
        'seriesId': seriesId,
        'seriesTitle': seriesTitle,
        'thumbnailUrl': thumbnailUrl,
        'episodeNumber': episodeNumber,
        'positionMs': positionMs,
        'durationMs': durationMs,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory WatchProgressEntry.fromJson(Map<String, dynamic> json) => WatchProgressEntry(
        postId: json['postId'] as String,
        seriesId: json['seriesId'] as String,
        seriesTitle: json['seriesTitle'] as String? ?? '',
        thumbnailUrl: json['thumbnailUrl'] as String?,
        episodeNumber: (json['episodeNumber'] as num?)?.toInt() ?? 1,
        positionMs: (json['positionMs'] as num?)?.toInt() ?? 0,
        durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
        updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now(),
      );
}

class WatchProgressService {
  static const _positionKeyPrefix = 'watch_pos_';
  static const _indexKey = 'continue_watching_v1';
  static const _maxIndexEntries = 20;

  // A position isn't worth remembering below this floor (barely
  // started — not really "in progress") or above this ceiling
  // (basically finished — showing it as "continue watching" would be
  // wrong, and it's better treated as done).
  static const _minFraction = 0.05;
  static const _maxFraction = 0.95;

  static final _client = SupabaseService.client;

  // Server sync is throttled separately (and far more coarsely) than
  // the local write above — the local write already happens on every
  // ~3s local-save tick (see video_feed_screen.dart's own throttle); a
  // DB upsert that often would be needlessly chatty. Keyed in-memory
  // per postId, so it resets each app launch — the first save after
  // opening just always syncs, which isn't a correctness issue.
  static final Map<String, DateTime> _lastServerSync = {};
  static const _serverSyncInterval = Duration(seconds: 15);

  static Future<void> savePosition(
    Post post,
    Duration position,
    Duration duration, {
    bool forceServerSync = false,
  }) async {
    if (duration.inMilliseconds <= 0) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('$_positionKeyPrefix${post.id}', position.inMilliseconds);

    // Only drama episodes surface in the Continue Watching row — a
    // regular feed post still gets its raw position remembered above
    // (harmless, and useful if resume is ever wanted there too), just
    // never added to the index this drives the UI from.
    if (post.seriesId == null) return;

    final fraction = position.inMilliseconds / duration.inMilliseconds;
    if (fraction < _minFraction || fraction > _maxFraction) return;

    final entry = WatchProgressEntry(
      postId: post.id,
      seriesId: post.seriesId!,
      seriesTitle: post.seriesTitle ?? '',
      thumbnailUrl: post.thumbnailUrl,
      episodeNumber: post.episodeNumber ?? 1,
      positionMs: position.inMilliseconds,
      durationMs: duration.inMilliseconds,
      updatedAt: DateTime.now(),
    );
    await _upsertIndex(prefs, entry);
    unawaited(_maybeSyncToServer(entry, force: forceServerSync));
  }

  static Future<void> _maybeSyncToServer(WatchProgressEntry entry, {bool force = false}) async {
    final last = _lastServerSync[entry.postId];
    if (!force && last != null && DateTime.now().difference(last) < _serverSyncInterval) return;
    _lastServerSync[entry.postId] = DateTime.now();

    final userId = SupabaseService.currentUserId;
    if (userId == null) return;
    try {
      await _client.from('watch_progress').upsert({
        'user_id': userId,
        'post_id': entry.postId,
        'series_id': entry.seriesId,
        'position_ms': entry.positionMs,
        'duration_ms': entry.durationMs,
        'updated_at': entry.updatedAt.toIso8601String(),
      }, onConflict: 'user_id,post_id');
    } catch (_) {
      // Phase 2 table not migrated yet, or a network hiccup — the
      // local write already succeeded, so this device's own Continue
      // Watching still works regardless of whether the sync lands.
    }
  }

  /// Prefers the server's position when one exists — by the time a
  /// viewer reopens an episode, the device that was last watching it
  /// has already force-flushed on dispose (see video_feed_screen.dart),
  /// so the server row is at least as fresh as this device's own local
  /// one, and is the only way a *different* device's progress reaches
  /// this one. Falls back to the local value, then null.
  static Future<Duration?> getPosition(String postId) async {
    final userId = SupabaseService.currentUserId;
    if (userId != null) {
      try {
        final row = await _client
            .from('watch_progress')
            .select('position_ms')
            .eq('user_id', userId)
            .eq('post_id', postId)
            .maybeSingle();
        final ms = (row?['position_ms'] as num?)?.toInt();
        if (ms != null && ms > 0) return Duration(milliseconds: ms);
      } catch (_) {
        // Falls through to the local value below.
      }
    }

    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt('$_positionKeyPrefix$postId');
    if (ms == null || ms <= 0) return null;
    return Duration(milliseconds: ms);
  }

  /// Bulk version of getPosition for a screen listing many episodes at
  /// once (series_detail_screen.dart) — one server round trip for the
  /// whole list instead of one per episode.
  static Future<Map<String, Duration>> getPositions(List<String> postIds) async {
    if (postIds.isEmpty) return {};

    final result = <String, Duration>{};
    final prefs = await SharedPreferences.getInstance();
    for (final id in postIds) {
      final ms = prefs.getInt('$_positionKeyPrefix$id');
      if (ms != null && ms > 0) result[id] = Duration(milliseconds: ms);
    }

    final userId = SupabaseService.currentUserId;
    if (userId != null) {
      try {
        final rows = await _client
            .from('watch_progress')
            .select('post_id, position_ms')
            .eq('user_id', userId)
            .inFilter('post_id', postIds);
        for (final row in (rows as List)) {
          final ms = (row['position_ms'] as num?)?.toInt();
          if (ms != null && ms > 0) result[row['post_id'] as String] = Duration(milliseconds: ms);
        }
      } catch (_) {
        // Phase 2 table not migrated yet — local-only result, same as
        // getPosition's single-item fallback.
      }
    }
    return result;
  }

  /// Called once an episode is effectively finished — removes it from
  /// Continue Watching (a completed episode isn't "in progress") and
  /// clears the raw resume position, so reopening it starts over rather
  /// than seeking to 1 second from the end.
  static Future<void> clearPosition(String postId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_positionKeyPrefix$postId');
    final entries = await _readIndex(prefs);
    entries.removeWhere((e) => e.postId == postId);
    await _writeIndex(prefs, entries);
    _lastServerSync.remove(postId);

    final userId = SupabaseService.currentUserId;
    if (userId != null) {
      try {
        await _client.from('watch_progress').delete().eq('user_id', userId).eq('post_id', postId);
      } catch (_) {}
    }
  }

  /// Merges this device's local index with the server's rows (Phase 2),
  /// so an episode watched partway on another device shows up here too
  /// — deduped by post, newest `updatedAt` wins.
  static Future<List<WatchProgressEntry>> getContinueWatching({int limit = 10}) async {
    final prefs = await SharedPreferences.getInstance();
    final localEntries = await _readIndex(prefs);

    final userId = SupabaseService.currentUserId;
    if (userId == null) return localEntries.take(limit).toList();

    List<WatchProgressEntry> serverEntries = [];
    try {
      final rows = await _client
          .from('watch_progress')
          .select('post_id, series_id, position_ms, duration_ms, updated_at')
          .eq('user_id', userId)
          .order('updated_at', ascending: false)
          .limit(limit * 2); // headroom before the merge/fraction filtering below
      final rawRows = (rows as List).cast<Map<String, dynamic>>();

      final postIds = rawRows.map((r) => r['post_id'] as String).toList();
      final posts = await PostService.getPostsByIds(postIds);
      final postById = {for (final p in posts) p.id: p};

      serverEntries = rawRows
          .map((row) {
            final post = postById[row['post_id']];
            // A watch_progress row whose post no longer resolves (e.g.
            // the episode was deleted) has nothing to render — drop it
            // rather than show a broken tile.
            if (post == null) return null;
            return WatchProgressEntry(
              postId: row['post_id'] as String,
              seriesId: (row['series_id'] as String?) ?? post.seriesId ?? '',
              seriesTitle: post.seriesTitle ?? '',
              thumbnailUrl: post.thumbnailUrl,
              episodeNumber: post.episodeNumber ?? 1,
              positionMs: (row['position_ms'] as num?)?.toInt() ?? 0,
              durationMs: (row['duration_ms'] as num?)?.toInt() ?? 0,
              updatedAt: DateTime.tryParse(row['updated_at'] as String? ?? '') ?? DateTime.now(),
            );
          })
          .whereType<WatchProgressEntry>()
          .toList();
    } catch (_) {
      // Phase 2 table not migrated yet, or offline — local-only result,
      // same as before this method knew about a server at all.
    }

    final byId = <String, WatchProgressEntry>{};
    for (final e in [...localEntries, ...serverEntries]) {
      final existing = byId[e.postId];
      if (existing == null || e.updatedAt.isAfter(existing.updatedAt)) {
        byId[e.postId] = e;
      }
    }
    final merged = byId.values.toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return merged.take(limit).toList();
  }

  static Future<void> _upsertIndex(SharedPreferences prefs, WatchProgressEntry entry) async {
    final entries = await _readIndex(prefs);
    entries.removeWhere((e) => e.postId == entry.postId);
    entries.insert(0, entry); // most-recently-watched first
    if (entries.length > _maxIndexEntries) {
      entries.removeRange(_maxIndexEntries, entries.length);
    }
    await _writeIndex(prefs, entries);
  }

  static Future<List<WatchProgressEntry>> _readIndex(SharedPreferences prefs) async {
    final raw = prefs.getString(_indexKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => WatchProgressEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      // Corrupt/old-format local data — safer to start clean than crash
      // the Dramas home screen over it.
      return [];
    }
  }

  static Future<void> _writeIndex(SharedPreferences prefs, List<WatchProgressEntry> entries) async {
    await prefs.setString(_indexKey, jsonEncode(entries.map((e) => e.toJson()).toList()));
  }
}
