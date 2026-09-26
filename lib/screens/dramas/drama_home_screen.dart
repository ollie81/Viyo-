import 'package:flutter/material.dart';
import '../../models/series.dart';
import '../../services/series_service.dart';
import '../../services/watch_progress_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/friendly_error.dart';
import '../../widgets/drama_sort_toggle.dart';
import '../../widgets/genre_chip_row.dart';
import '../../widgets/series_poster_card.dart';
import '../post/series_detail_screen.dart';
import '../video_feed_screen.dart';

/// The dedicated Short Drama home — previously drama discovery was
/// nested two levels deep (a tab inside Home's TabBar, and a section
/// inside Discover), with no place of its own. This assembles the
/// discovery queries that already existed in SeriesService (trending,
/// new, genre/sort browse) into proper sections rather than rebuilding
/// any of them, plus the two genuinely new rows: Continue Watching
/// (local-only, see WatchProgressService) and a real browse grid lifted
/// from feed_screen.dart's former Dramas tab.
class DramaHomeScreen extends StatefulWidget {
  const DramaHomeScreen({super.key});

  @override
  State<DramaHomeScreen> createState() => _DramaHomeScreenState();
}

class _DramaHomeScreenState extends State<DramaHomeScreen> {
  List<WatchProgressEntry> _continueWatching = [];
  List<Series> _trending = [];
  List<Series> _newReleases = [];
  bool _loadingRows = true;

  List<Series> _browseSeries = [];
  bool _loadingBrowse = true;
  String? _browseError;
  String _selectedGenre = GenreChipRow.all;
  DramaSort _selectedSort = DramaSort.newest;

  @override
  void initState() {
    super.initState();
    _loadRows();
    _loadBrowse();
  }

  Future<void> _loadRows() async {
    setState(() => _loadingRows = true);

    final continueWatching = await WatchProgressService.getContinueWatching();

    // Trending/New Releases are each independently best-effort — one
    // failing shouldn't blank the whole screen, same reasoning
    // feed_screen.dart already applies to its own For You/Following
    // pair.
    List<Series> trending = [];
    List<Series> newReleases = [];
    try {
      trending = await SeriesService.getAllSeries(sort: DramaSort.hot, limit: 10);
    } catch (_) {}
    try {
      newReleases = await SeriesService.getNewAiSeries(limit: 10);
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _continueWatching = continueWatching;
      _trending = trending;
      _newReleases = newReleases;
      _loadingRows = false;
    });
  }

  Future<void> _loadBrowse() async {
    setState(() {
      _loadingBrowse = true;
      _browseError = null;
    });
    try {
      final genre = _selectedGenre == GenreChipRow.all ? null : _selectedGenre;
      final series = await SeriesService.getAllSeries(genre: genre, sort: _selectedSort);
      if (!mounted) return;
      setState(() {
        _browseSeries = series;
        _loadingBrowse = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingBrowse = false;
          _browseError = friendlyErrorMessage(e);
        });
      }
    }
  }

  void _selectGenre(String genre) {
    if (genre == _selectedGenre) return;
    setState(() => _selectedGenre = genre);
    _loadBrowse();
  }

  void _selectSort(DramaSort sort) {
    if (sort == _selectedSort) return;
    setState(() => _selectedSort = sort);
    _loadBrowse();
  }

  Future<void> _refresh() => Future.wait([_loadRows(), _loadBrowse()]);

  void _openSeries(Series s) => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => SeriesDetailScreen(series: s)),
      );

  void _openContinueWatching(WatchProgressEntry e) => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VideoFeedScreen(initialPostId: e.postId, seriesId: e.seriesId),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final browseFailed = !_loadingBrowse && _browseSeries.isEmpty && _browseError != null;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome, color: AppColors.secondary, size: 20),
            SizedBox(width: 8),
            Text('Short Dramas'),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        color: AppColors.secondary,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            if (!_loadingRows && _continueWatching.isNotEmpty) ...[
              const SliverPadding(
                padding: EdgeInsets.fromLTRB(12, 14, 12, 8),
                sliver: SliverToBoxAdapter(child: _SectionLabel('CONTINUE WATCHING')),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 0, 0, 4),
                sliver: SliverToBoxAdapter(
                  child: _ContinueWatchingRow(entries: _continueWatching, onTap: _openContinueWatching),
                ),
              ),
            ],
            if (!_loadingRows && _trending.isNotEmpty) ...[
              const SliverPadding(
                padding: EdgeInsets.fromLTRB(12, 18, 12, 8),
                sliver: SliverToBoxAdapter(child: _SectionLabel('TRENDING')),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 0, 0, 4),
                sliver: SliverToBoxAdapter(
                  child: _SeriesRow(series: _trending, onTap: _openSeries),
                ),
              ),
            ],
            if (!_loadingRows && _newReleases.isNotEmpty) ...[
              const SliverPadding(
                padding: EdgeInsets.fromLTRB(12, 18, 12, 8),
                sliver: SliverToBoxAdapter(child: _SectionLabel('NEW RELEASES')),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 0, 0, 4),
                sliver: SliverToBoxAdapter(
                  child: _SeriesRow(series: _newReleases, onTap: _openSeries),
                ),
              ),
            ],
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(12, 18, 12, 8),
              sliver: SliverToBoxAdapter(child: _SectionLabel('BROWSE')),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              sliver: SliverToBoxAdapter(
                child: DramaSortToggle(selected: _selectedSort, onSelect: _selectSort),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
              sliver: SliverToBoxAdapter(
                child: GenreChipRow(selected: _selectedGenre, onSelect: _selectGenre),
              ),
            ),
            if (_loadingBrowse)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator(color: AppColors.secondary)),
              )
            else if (browseFailed)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: _DramaStateMessage.error(_browseError!, onRetry: _loadBrowse)),
              )
            else if (_browseSeries.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: _DramaStateMessage(
                    icon: Icons.auto_awesome,
                    title: 'No Dramas yet',
                    subtitle: 'Upload one from the + button to start a series.',
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.6,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) => SeriesPosterCard(series: _browseSeries[i], onTap: () => _openSeries(_browseSeries[i])),
                    childCount: _browseSeries.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(fontSize: 11, letterSpacing: 0.8, color: AppColors.textMuted, fontWeight: FontWeight.w700),
    );
  }
}

class _SeriesRow extends StatelessWidget {
  final List<Series> series;
  final void Function(Series) onTap;
  const _SeriesRow({required this.series, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 190,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(right: 12),
        itemCount: series.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, i) => SizedBox(
          width: 116,
          child: SeriesPosterCard(series: series[i], onTap: () => onTap(series[i])),
        ),
      ),
    );
  }
}

class _ContinueWatchingRow extends StatelessWidget {
  final List<WatchProgressEntry> entries;
  final void Function(WatchProgressEntry) onTap;
  const _ContinueWatchingRow({required this.entries, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 130,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(right: 12),
        itemCount: entries.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final e = entries[i];
          return GestureDetector(
            onTap: () => onTap(e),
            child: SizedBox(
              width: 92,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      width: 92,
                      height: 92,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          e.thumbnailUrl != null
                              ? Image.network(
                                  e.thumbnailUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(color: AppColors.surfaceBorder),
                                )
                              : Container(color: AppColors.surfaceBorder),
                          const Align(
                            alignment: Alignment.center,
                            child: Icon(Icons.play_circle_fill, color: Colors.white, size: 26),
                          ),
                          Align(
                            alignment: Alignment.bottomCenter,
                            child: LinearProgressIndicator(
                              value: e.fraction,
                              minHeight: 3,
                              backgroundColor: Colors.black45,
                              valueColor: const AlwaysStoppedAnimation(AppColors.secondary),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    e.seriesTitle.isEmpty ? 'Episode ${e.episodeNumber}' : e.seriesTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                  Text(
                    'Ep ${e.episodeNumber}',
                    style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Shared error/empty presentation for the Browse grid — small enough
/// (and different enough from feed_screen.dart's private equivalents,
/// which stay there for its other three tabs) that a local copy is
/// simpler than threading a shared widget across files for this alone.
class _DramaStateMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color iconColor;
  final VoidCallback? onRetry;

  const _DramaStateMessage({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.iconColor = AppColors.primary,
    this.onRetry,
  });

  factory _DramaStateMessage.error(String message, {required VoidCallback onRetry}) => _DramaStateMessage(
        icon: Icons.error_outline,
        title: "Couldn't load dramas",
        subtitle: message,
        iconColor: AppColors.danger,
        onRetry: onRetry,
      );

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(color: iconColor.withOpacity(0.12), shape: BoxShape.circle),
          child: Icon(icon, color: iconColor, size: 28),
        ),
        const SizedBox(height: 16),
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5, height: 1.4),
          ),
        ),
        if (onRetry != null) ...[
          const SizedBox(height: 14),
          OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ],
    );
  }
}
