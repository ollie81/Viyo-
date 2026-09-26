import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../models/post.dart';
import '../../models/series.dart';
import '../../services/profile_service.dart';
import '../../services/series_service.dart';
import '../../services/supabase_service.dart';
import '../../services/watch_progress_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/episode_lock.dart';
import '../../utils/friendly_error.dart';
import '../../widgets/comments_sheet.dart';
import '../../widgets/guest_gate.dart';
import '../../widgets/series_poster_card.dart';
import '../video_feed_screen.dart';

/// A series' full episode list — Episode 1, 2, 3... in order, each
/// showing its lock state at a glance. Tapping an episode opens it in
/// VideoFeedScreen scoped to this series (seriesId) — swiping past it
/// moves through this series' remaining episodes in order, and playback
/// auto-advances into the next one when the current one finishes,
/// instead of backing out to pick the next episode by hand.
class SeriesDetailScreen extends StatefulWidget {
  final Series series;
  const SeriesDetailScreen({super.key, required this.series});

  @override
  State<SeriesDetailScreen> createState() => _SeriesDetailScreenState();
}

class _SeriesDetailScreenState extends State<SeriesDetailScreen> {
  // A local mutable copy so a status change (see _StatusToggle) can
  // update this screen immediately without re-fetching the whole
  // series — widget.series itself is the immutable value this screen
  // was pushed with.
  late Series _series = widget.series;
  List<Post> _episodes = [];
  List<Series> _similarSeries = [];
  Map<String, Duration> _resumePositions = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final episodes = await SeriesService.getSeriesEpisodes(widget.series.id);
      if (!mounted) return;
      setState(() => _episodes = episodes);
      unawaited(_loadResumePositions(episodes));
      unawaited(_loadSimilarSeries());
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyErrorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Best-effort, doesn't block the episode list itself — "Similar
  /// dramas" is a nice-to-have below the fold, not something worth a
  /// loading state of its own.
  Future<void> _loadSimilarSeries() async {
    try {
      final similar = await SeriesService.getAllSeries(
        genre: widget.series.genre,
        sort: DramaSort.hot,
        limit: 10,
      );
      if (!mounted) return;
      setState(() {
        _similarSeries = similar.where((s) => s.id != widget.series.id).toList();
      });
    } catch (_) {
      // Leaves the section empty rather than surfacing an error over a
      // secondary recommendation.
    }
  }

  /// Local-only resume positions (see WatchProgressService) for
  /// whichever episodes have one — powers each tile's "Resume" label.
  Future<void> _loadResumePositions(List<Post> episodes) async {
    final positions = <String, Duration>{};
    for (final ep in episodes) {
      final pos = await WatchProgressService.getPosition(ep.id);
      if (pos != null) positions[ep.id] = pos;
    }
    if (!mounted) return;
    setState(() => _resumePositions = positions);
  }

  @override
  Widget build(BuildContext context) {
    final series = _series;
    final viewerId = SupabaseService.currentUserId;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: Text(series.title, overflow: TextOverflow.ellipsis),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.secondary))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, color: AppColors.textSecondary, size: 32),
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                        ),
                        const SizedBox(height: 16),
                        OutlinedButton(onPressed: _load, child: const Text('Retry')),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
              onRefresh: _load,
              color: AppColors.secondary,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  _SeriesHeader(
                    series: series,
                    episodeCount: _episodes.length,
                    viewerId: viewerId,
                    onStatusChanged: (status) => setState(() => _series = _series.copyWith(status: status)),
                  ),
                  const SizedBox(height: 18),
                  const Text('EPISODES', style: TextStyle(fontSize: 11, letterSpacing: 0.8, color: AppColors.textMuted, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  if (_episodes.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 20),
                      child: Center(
                        child: Text('No episodes yet', style: TextStyle(color: AppColors.textMuted)),
                      ),
                    )
                  else
                    ..._episodes.map((ep) => _EpisodeTile(
                          episode: ep,
                          locked: isEpisodeLocked(ep, viewerId: viewerId),
                          resumePosition: _resumePositions[ep.id],
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => VideoFeedScreen(
                                initialPostId: ep.id,
                                seriesId: series.id,
                              ),
                            ),
                          ),
                          onComment: () => showCommentsSheet(
                            context,
                            ep,
                            onCommentAdded: () {
                              if (!mounted) return;
                              setState(() {
                                _episodes = _episodes
                                    .map((p) => p.id == ep.id ? p.copyWith(commentCount: p.commentCount + 1) : p)
                                    .toList();
                              });
                            },
                          ),
                        )),
                  if (_similarSeries.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    const Text('SIMILAR DRAMAS', style: TextStyle(fontSize: 11, letterSpacing: 0.8, color: AppColors.textMuted, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 190,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _similarSeries.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 12),
                        itemBuilder: (_, i) {
                          final s = _similarSeries[i];
                          return SizedBox(
                            width: 116,
                            child: SeriesPosterCard(
                              series: s,
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => SeriesDetailScreen(series: s)),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}

class _SeriesHeader extends StatelessWidget {
  final Series series;
  final int episodeCount;
  final String? viewerId;
  final ValueChanged<String>? onStatusChanged;
  const _SeriesHeader({
    required this.series,
    required this.episodeCount,
    required this.viewerId,
    this.onStatusChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.card(borderColor: AppColors.secondary.withOpacity(0.35)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 64,
              height: 90,
              child: series.coverImageUrl != null
                  ? CachedNetworkImage(
                      imageUrl: series.coverImageUrl!,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => Container(
                        color: AppColors.surfaceBorder,
                        child: const Icon(Icons.auto_awesome, color: AppColors.secondary),
                      ),
                    )
                  : Container(
                      color: AppColors.surfaceBorder,
                      child: const Icon(Icons.auto_awesome, color: AppColors.secondary),
                    ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(series.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text('by @${series.authorUsername ?? 'creator'}', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                const SizedBox(height: 8),
                if (series.description.trim().isNotEmpty)
                  Text(series.description, style: const TextStyle(fontSize: 12.5, height: 1.35, color: AppColors.textSecondary)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _Pill(icon: Icons.movie_outlined, label: '$episodeCount episodes'),
                    const SizedBox(width: 8),
                    _Pill(icon: Icons.monetization_on_outlined, label: '${series.coinPricePerEpisode}/ep after free'),
                    // Inert until a `status` column exists on `series`
                    // — see the field's own doc comment in series.dart.
                    if (series.status != null) ...[
                      const SizedBox(width: 8),
                      viewerId == series.userId
                          ? _StatusToggle(
                              seriesId: series.id,
                              status: series.status!,
                              onChanged: (s) => onStatusChanged?.call(s),
                            )
                          : _Pill(
                              icon: series.status == 'completed' ? Icons.check_circle_outline : Icons.autorenew,
                              label: series.status == 'completed' ? 'Completed' : 'Ongoing',
                            ),
                    ],
                  ],
                ),
                if (viewerId != series.userId) ...[
                  const SizedBox(height: 10),
                  _FollowCreatorButton(creatorId: series.userId, creatorUsername: series.authorUsername),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Follows the *creator*, not this specific series — a true per-series
/// follow needs a `series_follows` table this codebase can't create
/// without a migration (see the Short Drama plan), so this reuses the
/// existing creator-level `follows` table and is labeled honestly
/// rather than implying it's series-scoped.
class _FollowCreatorButton extends StatefulWidget {
  final String creatorId;
  final String? creatorUsername;
  const _FollowCreatorButton({required this.creatorId, this.creatorUsername});

  @override
  State<_FollowCreatorButton> createState() => _FollowCreatorButtonState();
}

class _FollowCreatorButtonState extends State<_FollowCreatorButton> {
  bool? _following; // null while the initial check is still loading
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final viewerId = SupabaseService.currentUserId;
    if (viewerId == null) {
      if (mounted) setState(() => _following = false);
      return;
    }
    try {
      final following = await ProfileService.isFollowing(viewerId, widget.creatorId);
      if (mounted) setState(() => _following = following);
    } catch (_) {
      if (mounted) setState(() => _following = false);
    }
  }

  Future<void> _toggle() async {
    if (_busy || _following == null) return;
    if (!await GuestGate.allow(context, action: 'follow this creator')) return;
    final viewerId = SupabaseService.currentUserId;
    if (viewerId == null) return;

    setState(() => _busy = true);
    try {
      if (_following!) {
        await ProfileService.unfollow(viewerId, widget.creatorId);
      } else {
        await ProfileService.follow(viewerId, widget.creatorId);
      }
      if (mounted) setState(() => _following = !_following!);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyErrorMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_following == null) return const SizedBox(height: 32);
    final following = _following!;
    return SizedBox(
      height: 32,
      child: following
          ? OutlinedButton(
              onPressed: _busy ? null : _toggle,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                side: const BorderSide(color: AppColors.surfaceBorder),
              ),
              child: Text('Following', style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
            )
          : ElevatedButton(
              onPressed: _busy ? null : _toggle,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.secondary,
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              child: Text(
                widget.creatorUsername != null ? 'Follow @${widget.creatorUsername}' : 'Follow creator',
                style: const TextStyle(fontSize: 12.5, color: Colors.black, fontWeight: FontWeight.w700),
              ),
            ),
    );
  }
}

/// The owner's own version of the status pill — tap to flip between
/// Ongoing and Completed. A direct RLS-scoped write (see
/// SeriesService.updateStatus): only ever shown to the series' own
/// owner, for whom the update policy already allows this without
/// going through the backend.
class _StatusToggle extends StatefulWidget {
  final String seriesId;
  final String status;
  final ValueChanged<String> onChanged;
  const _StatusToggle({required this.seriesId, required this.status, required this.onChanged});

  @override
  State<_StatusToggle> createState() => _StatusToggleState();
}

class _StatusToggleState extends State<_StatusToggle> {
  bool _busy = false;

  Future<void> _toggle() async {
    if (_busy) return;
    final next = widget.status == 'completed' ? 'ongoing' : 'completed';
    setState(() => _busy = true);
    try {
      await SeriesService.updateStatus(widget.seriesId, next);
      widget.onChanged(next);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyErrorMessage(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final completed = widget.status == 'completed';
    return GestureDetector(
      onTap: _toggle,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.secondary.withOpacity(0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_busy)
              const SizedBox(
                width: 10,
                height: 10,
                child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.secondary),
              )
            else
              Icon(
                completed ? Icons.check_circle_outline : Icons.autorenew,
                size: 11,
                color: AppColors.secondary,
              ),
            const SizedBox(width: 4),
            Text(
              completed ? 'Completed' : 'Ongoing',
              style: const TextStyle(fontSize: 10.5, color: AppColors.secondary, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 2),
            const Icon(Icons.unfold_more, size: 11, color: AppColors.secondary),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final String label;
  const _Pill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: AppColors.textMuted),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted)),
        ],
      ),
    );
  }
}

class _EpisodeTile extends StatelessWidget {
  final Post episode;
  final bool locked;
  final Duration? resumePosition;
  final VoidCallback onTap;
  final VoidCallback onComment;
  const _EpisodeTile({
    required this.episode,
    required this.locked,
    this.resumePosition,
    required this.onTap,
    required this.onComment,
  });

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: AppTheme.card(),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 48,
                height: 68,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    episode.thumbnailUrl != null
                        ? CachedNetworkImage(
                            imageUrl: episode.thumbnailUrl!,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => Container(color: AppColors.surfaceBorder),
                          )
                        : Container(color: AppColors.surfaceBorder),
                    if (locked)
                      Container(
                        color: Colors.black.withOpacity(0.5),
                        child: const Icon(Icons.lock_outline, color: Colors.white, size: 16),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Episode ${episode.episodeNumber ?? ''}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  if (resumePosition != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Resume · ${_formatDuration(resumePosition!)}',
                      style: const TextStyle(color: AppColors.secondary, fontSize: 11.5, fontWeight: FontWeight.w600),
                    ),
                  ] else if (episode.caption.trim().isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      episode.caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5),
                    ),
                  ],
                ],
              ),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onComment,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.mode_comment_outlined, color: AppColors.textMuted, size: 18),
                    const SizedBox(height: 2),
                    Text('${episode.commentCount}', style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              locked ? Icons.lock_outline : Icons.play_circle_outline,
              color: locked ? AppColors.textMuted : AppColors.secondary,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}
