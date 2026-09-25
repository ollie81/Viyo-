import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../models/post.dart';
import '../../models/series.dart';
import '../../services/series_service.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/episode_lock.dart';
import '../../utils/friendly_error.dart';
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
  List<Post> _episodes = [];
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
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyErrorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final series = widget.series;
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
                  _SeriesHeader(series: series, episodeCount: _episodes.length),
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
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => VideoFeedScreen(
                                initialPostId: ep.id,
                                seriesId: series.id,
                              ),
                            ),
                          ),
                        )),
                ],
              ),
            ),
    );
  }
}

class _SeriesHeader extends StatelessWidget {
  final Series series;
  final int episodeCount;
  const _SeriesHeader({required this.series, required this.episodeCount});

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
                  ],
                ),
              ],
            ),
          ),
        ],
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
  final VoidCallback onTap;
  const _EpisodeTile({required this.episode, required this.locked, required this.onTap});

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
                  if (episode.caption.trim().isNotEmpty) ...[
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
