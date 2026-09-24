import '../models/post.dart';
import '../models/series.dart';

/// Whether an episode should show a paywall to the given viewer.
///
/// The creator always sees their own episodes unlocked, and the first
/// [kFreeEpisodeCount] episodes of any series are free for everyone —
/// this mirrors episodes.py's own free-pass logic exactly so the UI
/// never shows a locked state the backend would actually let through
/// for free. Only a real, server-confirmed episode_unlocks row (or, for
/// a locked episode, [Post.unlockedByMe] read fresh from that table)
/// removes the lock; there is no case where this returns false for
/// content the viewer hasn't actually paid for.
bool isEpisodeLocked(Post episode, {required String? viewerId}) {
  if (!episode.isEpisode) return false;
  if (viewerId != null && episode.userId == viewerId) return false;
  final episodeNumber = episode.episodeNumber ?? 1;
  if (episodeNumber <= kFreeEpisodeCount) return false;
  return !episode.unlockedByMe;
}
