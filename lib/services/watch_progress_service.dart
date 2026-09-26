import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/post.dart';

/// Per-device "where did I leave off" tracking — local-only, not synced
/// across devices. This is the deliberate lightweight-first version: a
/// real synced Continue Watching needs a `watch_progress` table this
/// codebase can't create without the user running a migration (see the
/// Short Drama plan). Every method here is storage-agnostic in its
/// signature (Post + Duration in, Duration/entries out) specifically so
/// swapping the body for a backend-synced implementation later doesn't
/// change any call site.
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

  static Future<void> savePosition(Post post, Duration position, Duration duration) async {
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
  }

  static Future<Duration?> getPosition(String postId) async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt('$_positionKeyPrefix$postId');
    if (ms == null || ms <= 0) return null;
    return Duration(milliseconds: ms);
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
  }

  static Future<List<WatchProgressEntry>> getContinueWatching({int limit = 10}) async {
    final prefs = await SharedPreferences.getInstance();
    final entries = await _readIndex(prefs);
    return entries.take(limit).toList();
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
