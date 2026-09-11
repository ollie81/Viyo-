import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';

/// Reporting + blocking. Both `reports` and `blocks` are plain
/// RLS-scoped tables (see the SQL in this repo's README/setup notes) —
/// there's no backend involvement needed for either: a report is just
/// "insert a row only I can create, that nobody but the app's operator
/// can read back", and a block is "manage my own rows in a table only I
/// can see", the same shape as `likes` and `follows` already use.
class ModerationService {
  static final _client = SupabaseService.client;

  /// Fixed reason list shown in the report sheet — kept server-side-free
  /// (a plain string column) rather than a Postgres enum, since there's
  /// no migration access from this codebase to change one later.
  static const reportReasons = <String>[
    'Spam',
    'Harassment or bullying',
    'Hate speech',
    'Nudity or sexual content',
    'Violence or dangerous behavior',
    'Misinformation',
    'Other',
  ];

  static Future<void> submitReport({
    required String reporterId,
    required String targetType, // 'post' or 'user'
    required String targetId,
    required String reason,
    String? details,
  }) async {
    await _client.from('reports').insert({
      'reporter_id': reporterId,
      'target_type': targetType,
      'target_id': targetId,
      'reason': reason,
      'details': details,
    });
  }

  static Future<void> blockUser(String blockerId, String blockedId) async {
    try {
      await _client.from('blocks').insert({
        'blocker_id': blockerId,
        'blocked_id': blockedId,
      });
    } on PostgrestException catch (e) {
      // Unique-violation — already blocked. Nothing left to do.
      if (e.code == '23505') return;
      rethrow;
    }
  }

  static Future<void> unblockUser(String blockerId, String blockedId) async {
    await _client
        .from('blocks')
        .delete()
        .eq('blocker_id', blockerId)
        .eq('blocked_id', blockedId);
  }

  static Future<bool> isBlocked(String blockerId, String blockedId) async {
    final rows = await _client
        .from('blocks')
        .select('blocker_id')
        .eq('blocker_id', blockerId)
        .eq('blocked_id', blockedId)
        .limit(1);
    return (rows as List).isNotEmpty;
  }

  /// Every user id that should be invisible to `myId` — everyone they've
  /// blocked, and everyone who's blocked them (blocking is mutual: if
  /// someone blocked you, you shouldn't keep seeing their posts either).
  /// Used to filter feeds/discovery client-side, the same shape as
  /// PostService's own `_withLikedByMe` helper.
  static Future<Set<String>> getHiddenUserIds(String myId) async {
    try {
      final rows = await _client
          .from('blocks')
          .select('blocker_id, blocked_id')
          .or('blocker_id.eq.$myId,blocked_id.eq.$myId');
      final ids = <String>{};
      for (final r in (rows as List)) {
        final blocker = r['blocker_id'] as String;
        final blocked = r['blocked_id'] as String;
        ids.add(blocker == myId ? blocked : blocker);
      }
      return ids;
    } catch (_) {
      // Best-effort — a failed lookup should mean blocks don't apply to
      // this load, not that the whole feed/discovery fails.
      return {};
    }
  }
}
