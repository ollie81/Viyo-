import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../models/series.dart';
import '../theme/app_theme.dart';

/// A tall movie-poster-style card for one series: cover art, title
/// overlaid at the bottom over a gradient, and a genre pill underneath
/// — the card used everywhere a series is browsed (the Dramas tab's
/// grid, Discover's New/Trending Series rows), so the whole app reads
/// as one system instead of every list inventing its own tile shape.
class SeriesPosterCard extends StatelessWidget {
  final Series series;
  final VoidCallback onTap;
  // Set only by rows that actually rank by trending signal (see
  // SeriesService.getTrendingLabels) — e.g. 'TRENDING NOW'/'RISING
  // FAST'/'NEW & POPULAR'. Left null anywhere else (Browse, Similar
  // Dramas, New Releases) so the label never implies a ranking that
  // row isn't actually using.
  final String? trendingLabel;

  const SeriesPosterCard({super.key, required this.series, required this.onTap, this.trendingLabel});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 2 / 3,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  series.coverImageUrl != null
                      ? CachedNetworkImage(
                          imageUrl: series.coverImageUrl!,
                          fit: BoxFit.cover,
                          // Caps decode size regardless of the source
                          // file's own resolution — see
                          // RetryableNetworkImage's own comment for
                          // why this matters specifically on web.
                          memCacheWidth: 480,
                          errorWidget: (_, __, ___) => const _PosterPlaceholder(),
                        )
                      : const _PosterPlaceholder(),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(8, 24, 8, 8),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.black87],
                        ),
                      ),
                      child: Text(
                        series.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ),
                  if (series.episodeCount > 0)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.55),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '${series.episodeCount} ep',
                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  if (trendingLabel != null)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.secondary,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          trendingLabel!,
                          style: const TextStyle(color: Colors.black, fontSize: 8.5, fontWeight: FontWeight.w800, letterSpacing: 0.2),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: AppColors.surfaceBorder),
            ),
            child: Text(
              series.genre,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 10.5, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown while a series has no cover yet (new upload still backfilling,
/// or the auto-capture hasn't landed) — a soft brand-colored gradient
/// rather than a flat grey fill, so an empty poster still reads as a
/// designed tile instead of a broken/missing image.
class _PosterPlaceholder extends StatelessWidget {
  const _PosterPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.secondary.withOpacity(0.22),
            AppColors.surface,
          ],
        ),
      ),
      child: const Center(
        child: Icon(Icons.auto_awesome, color: AppColors.secondary, size: 28),
      ),
    );
  }
}
