import 'package:flutter/material.dart';
import '../models/series.dart';
import '../theme/app_theme.dart';

/// Horizontal scrollable genre filter — "All" plus every entry in
/// kDramaGenres — used above the Dramas tab's poster grid.
class GenreChipRow extends StatelessWidget {
  static const all = 'All';

  final String selected;
  final ValueChanged<String> onSelect;

  const GenreChipRow({super.key, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final genres = [all, ...kDramaGenres];
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: genres.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (ctx, i) {
          final genre = genres[i];
          final isSelected = genre == selected;
          return GestureDetector(
            onTap: () => onSelect(genre),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isSelected ? AppColors.secondary.withOpacity(0.18) : AppColors.surface,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: isSelected ? AppColors.secondary : AppColors.surfaceBorder),
              ),
              child: Text(
                genre,
                style: TextStyle(
                  fontSize: 12.5,
                  color: isSelected ? AppColors.secondary : AppColors.textSecondary,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.normal,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
