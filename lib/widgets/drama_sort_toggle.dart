import 'package:flutter/material.dart';
import '../models/series.dart';
import '../theme/app_theme.dart';

/// A compact 3-way segmented control (New / Popular / Hot) for the
/// Dramas tab's poster grid — sits alongside GenreChipRow, but this is
/// ordering, not a content filter, so it gets its own fixed-width
/// control instead of one more scrollable chip.
class DramaSortToggle extends StatelessWidget {
  final DramaSort selected;
  final ValueChanged<DramaSort> onSelect;

  const DramaSortToggle({super.key, required this.selected, required this.onSelect});

  static const _options = [
    (DramaSort.newest, 'New', Icons.fiber_new_outlined),
    (DramaSort.popular, 'Popular', Icons.trending_up),
    (DramaSort.hot, 'Hot', Icons.local_fire_department_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Row(
        children: _options.map((o) {
          final (value, label, icon) = o;
          final isSelected = value == selected;
          return Expanded(
            child: GestureDetector(
              onTap: () => onSelect(value),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 7),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.secondary.withOpacity(0.18) : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 14, color: isSelected ? AppColors.secondary : AppColors.textMuted),
                    const SizedBox(width: 5),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.normal,
                        color: isSelected ? AppColors.secondary : AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
