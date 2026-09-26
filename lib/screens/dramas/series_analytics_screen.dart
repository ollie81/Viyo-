import 'package:flutter/material.dart';
import '../../models/series.dart';
import '../../models/series_analytics.dart';
import '../../services/series_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/friendly_error.dart';

/// A series' own creator looking at how it's actually doing — views,
/// unique viewers, followers, saves, and per-episode completion/
/// drop-off. The backend already refuses this to anyone but the
/// series' owner; this screen is only ever reachable from
/// series_detail_screen.dart's owner-only entry point, but the
/// friendly 403 still renders sensibly if that's ever bypassed.
class SeriesAnalyticsScreen extends StatefulWidget {
  final Series series;
  const SeriesAnalyticsScreen({super.key, required this.series});

  @override
  State<SeriesAnalyticsScreen> createState() => _SeriesAnalyticsScreenState();
}

class _SeriesAnalyticsScreenState extends State<SeriesAnalyticsScreen> {
  SeriesAnalytics? _analytics;
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
      final analytics = await SeriesService.getSeriesAnalytics(widget.series.id);
      if (!mounted) return;
      setState(() => _analytics = analytics);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyErrorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: Text('Analytics · ${widget.series.title}', overflow: TextOverflow.ellipsis),
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
                        Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
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
                    padding: const EdgeInsets.all(16),
                    children: [
                      _summaryGrid(_analytics!),
                      if (_analytics!.bestCompletionEpisode != null) ...[
                        const SizedBox(height: 16),
                        _insightCard(_analytics!.bestCompletionEpisode!),
                      ],
                      const SizedBox(height: 24),
                      const Text(
                        'EPISODE PERFORMANCE',
                        style: TextStyle(fontSize: 11, letterSpacing: 0.8, color: AppColors.textMuted, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 10),
                      if (_analytics!.episodes.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 20),
                          child: Center(child: Text('No episodes yet', style: TextStyle(color: AppColors.textMuted))),
                        )
                      else
                        ..._analytics!.episodes.map(_episodeRow),
                    ],
                  ),
                ),
    );
  }

  Widget _summaryGrid(SeriesAnalytics a) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.9,
      children: [
        _statTile('Total views', '${a.totalViews}', Icons.visibility_outlined),
        _statTile('Unique viewers', '${a.totalUniqueViewers}', Icons.people_outline),
        _statTile('Followers', '${a.followerCount}', Icons.favorite_border),
        _statTile('Saves', '${a.watchlistCount}', Icons.bookmark_border_rounded),
      ],
    );
  }

  Widget _statTile(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 16, color: AppColors.secondary),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
        ],
      ),
    );
  }

  /// The one growth-insight line this screen shows — genuinely computed
  /// from this series' own data, never a generic/fabricated tip. Only
  /// rendered when there's actually an episode with completion data to
  /// name (see SeriesAnalytics.bestCompletionEpisode).
  Widget _insightCard(EpisodeAnalytics best) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.card(borderColor: AppColors.secondary.withOpacity(0.35)),
      child: Row(
        children: [
          const Icon(Icons.insights_rounded, size: 18, color: AppColors.secondary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Episode ${best.episodeNumber} has your highest completion rate at ${best.completionRate!.toStringAsFixed(0)}%.',
              style: const TextStyle(fontSize: 12.5, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }

  Widget _episodeRow(EpisodeAnalytics ep) {
    final hasData = ep.completionRate != null;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: AppTheme.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Episode ${ep.episodeNumber}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              const Spacer(),
              Icon(Icons.visibility_outlined, size: 12, color: AppColors.textMuted),
              const SizedBox(width: 3),
              Text('${ep.viewCount}', style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
              const SizedBox(width: 10),
              Icon(Icons.favorite_border, size: 12, color: AppColors.textMuted),
              const SizedBox(width: 3),
              Text('${ep.likeCount}', style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
              const SizedBox(width: 10),
              Icon(Icons.mode_comment_outlined, size: 12, color: AppColors.textMuted),
              const SizedBox(width: 3),
              Text('${ep.commentCount}', style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
            ],
          ),
          const SizedBox(height: 10),
          if (hasData) ...[
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: ep.completionRate! / 100,
                      minHeight: 6,
                      backgroundColor: AppColors.surfaceBorder,
                      valueColor: const AlwaysStoppedAnimation(AppColors.secondary),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text('${ep.completionRate!.toStringAsFixed(0)}%', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${ep.uniqueViewers} viewer${ep.uniqueViewers == 1 ? '' : 's'} · completion rate',
              style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted),
            ),
          ] else
            const Text(
              'Not enough watch data yet',
              style: TextStyle(fontSize: 11, color: AppColors.textMuted, fontStyle: FontStyle.italic),
            ),
        ],
      ),
    );
  }
}
