import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'post_service.dart';
import 'series_service.dart';

/// Local, client-only scheduling for "publish this episode later" (see
/// upload_ai_drama_screen.dart). A scheduled episode is inserted as a
/// real post right away, just with `is_private: true` — the same
/// column every feed/discover/series query already excludes it by
/// (see PostService.setPrivate, SeriesService.getSeriesEpisodes). This
/// service only remembers *when* to flip that back to public.
///
/// Real, stated limitation: this can only fire while the SAME device
/// that scheduled it reopens the app after the target time (see
/// checkAndPublishDue, called on Dramas home load) — there is no
/// server-side cron in this backend to publish while the app is
/// closed. A true always-on schedule needs a `posts.publish_at` column
/// plus a Supabase pg_cron job flipping it, which needs a migration
/// this sandbox can't run — this is the immediate, zero-migration
/// version, same "ship the honest degraded version now, hand over SQL
/// for the real one" posture as series.status.
class ScheduledReleaseService {
  static const _key = 'scheduled_releases_v1';

  static Future<void> schedule(String postId, DateTime publishAt) async {
    final prefs = await SharedPreferences.getInstance();
    final map = _readMap(prefs);
    map[postId] = publishAt.toIso8601String();
    await prefs.setString(_key, jsonEncode(map));
  }

  static Future<void> clear(String postId) async {
    final prefs = await SharedPreferences.getInstance();
    final map = _readMap(prefs);
    if (map.remove(postId) != null) {
      await prefs.setString(_key, jsonEncode(map));
    }
  }

  /// Bulk lookup for a screen listing several episodes at once
  /// (series_detail_screen.dart) — one local-storage read instead of
  /// one per episode.
  static Future<Map<String, DateTime>> getScheduledTimes(List<String> postIds) async {
    final prefs = await SharedPreferences.getInstance();
    final map = _readMap(prefs);
    final result = <String, DateTime>{};
    for (final id in postIds) {
      final raw = map[id] as String?;
      final parsed = raw == null ? null : DateTime.tryParse(raw);
      if (parsed != null) result[id] = parsed;
    }
    return result;
  }

  /// Publishes any locally-scheduled episode whose time has passed —
  /// best-effort per entry, so one failed flip doesn't block the rest
  /// or get retried forever if it's actually a permanent error (a
  /// deleted post, say) than never sets a value into this map back.
  static Future<void> checkAndPublishDue() async {
    final prefs = await SharedPreferences.getInstance();
    final map = _readMap(prefs);
    if (map.isEmpty) return;

    final now = DateTime.now();
    final due = <String>[];
    for (final entry in map.entries) {
      final when = DateTime.tryParse(entry.value as String);
      if (when != null && !when.isAfter(now)) due.add(entry.key);
    }
    if (due.isEmpty) return;

    for (final postId in due) {
      try {
        await PostService.setPrivate(postId, false);
        unawaited(SeriesService.notifyNewEpisode(postId));
        map.remove(postId);
      } catch (_) {
        // Leave it scheduled — retried next time this check runs.
      }
    }
    await prefs.setString(_key, jsonEncode(map));
  }

  static Map<String, dynamic> _readMap(SharedPreferences prefs) {
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return {};
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      // Corrupt/old-format local data — safer to start clean than crash
      // over it.
      return {};
    }
  }
}
