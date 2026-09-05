import 'package:flutter/material.dart';
import '../models/leaderboard_entry.dart';
import '../services/leaderboard_service.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';

/// Ranks creators by Viyo Coins actually earned in the last 7 days —
/// real transaction totals from the backend, never an invented score.
/// Competitive status-checking ("did I pass them yet?") is a strong
/// daily-return driver on its own, on top of what earning the coins
/// already rewards.
class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  WeeklyLeaderboard? _board;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final board = await LeaderboardService.getWeeklyLeaderboard();
      if (mounted) setState(() => _board = board);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not load the leaderboard: $e');
    }
  }

  Color? _medalColor(int rank) {
    switch (rank) {
      case 1:
        return const Color(0xFFFFD700);
      case 2:
        return const Color(0xFFC0C0C0);
      case 3:
        return const Color(0xFFCD7F32);
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final board = _board;
    final myUserId = SupabaseService.currentUserId;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: const Text('Weekly Leaderboard'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: AppColors.primary,
        child: _error != null
            ? ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!, style: const TextStyle(color: AppColors.danger)),
                  ),
                ],
              )
            : board == null
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: AppTheme.glowCard(glowColor: AppColors.coin, glowOpacity: 0.15),
                        child: Row(
                          children: [
                            const Icon(Icons.emoji_events, color: AppColors.coin, size: 30),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    board.myRank != null
                                        ? 'You\'re #${board.myRank} this week'
                                        : 'Not ranked yet this week',
                                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    board.myCoinsEarned != null
                                        ? '${board.myCoinsEarned} coins earned in the last ${board.windowDays} days'
                                        : 'Earn coins to appear on the board',
                                    style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      if (board.entries.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 30),
                          child: Center(
                            child: Text(
                              'No one has earned coins yet this week — be the first.',
                              style: TextStyle(color: AppColors.textSecondary),
                            ),
                          ),
                        )
                      else
                        for (final entry in board.entries) _entryRow(entry, isMe: entry.userId == myUserId),
                    ],
                  ),
      ),
    );
  }

  Widget _entryRow(LeaderboardEntry entry, {required bool isMe}) {
    final medal = _medalColor(entry.rank);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: AppTheme.card(borderColor: isMe ? AppColors.primary.withOpacity(0.5) : null),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: medal != null
                ? Icon(Icons.emoji_events, color: medal, size: 20)
                : Text('${entry.rank}', style: const TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 8),
          CircleAvatar(
            radius: 16,
            backgroundColor: AppColors.surfaceBorder,
            backgroundImage: entry.avatarUrl != null ? NetworkImage(entry.avatarUrl!) : null,
            child: entry.avatarUrl == null
                ? Text(entry.displayName.isNotEmpty ? entry.displayName[0].toUpperCase() : '?', style: const TextStyle(fontSize: 12))
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isMe ? '${entry.displayName} (You)' : entry.displayName,
              style: TextStyle(fontWeight: isMe ? FontWeight.w700 : FontWeight.w500, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.monetization_on, size: 14, color: AppColors.coin),
              const SizedBox(width: 3),
              Text('${entry.coinsEarned}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.coin)),
            ],
          ),
        ],
      ),
    );
  }
}
