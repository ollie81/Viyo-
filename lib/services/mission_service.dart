import '../models/mission.dart';
import 'supabase_service.dart';

class MissionService {
  static final _client = SupabaseService.client;

  /// Returns today's missions merged with the user's progress. Ensures a
  /// user_missions row exists for each active mission today (idempotent).
  static Future<List<Mission>> getTodayMissions(String userId) async {
    final today = DateTime.now().toIso8601String().substring(0, 10);

    final missions = await _client
        .from('missions')
        .select()
        .eq('is_active', true);

    // Ensure rows exist for today (upsert is a no-op if already present).
    for (final m in missions) {
      await _client.from('user_missions').upsert(
        {
          'user_id': userId,
          'mission_id': m['id'],
          'mission_date': today,
        },
        onConflict: 'user_id,mission_id,mission_date',
        ignoreDuplicates: true,
      );
    }

    final userMissions = await _client
        .from('user_missions')
        .select()
        .eq('user_id', userId)
        .eq('mission_date', today);

    final progressById = {
      for (final um in userMissions) um['mission_id']: um,
    };

    return (missions as List).map((m) {
      final um = progressById[m['id']];
      return Mission.fromJson({
        ...m,
        'progress_count': um?['progress_count'] ?? 0,
        'completed': um?['completed'] ?? false,
        'claimed': um?['claimed'] ?? false,
        // stash the user_missions row id for claiming
        '_user_mission_id': um?['id'],
      });
    }).toList();
  }

  static Future<Map<String, dynamic>> claimMission({
    required String userId,
    required String userMissionId,
  }) async {
    return await _client.rpc('claim_mission', params: {
      'p_user_id': userId,
      'p_user_mission_id': userMissionId,
    });
  }
}
