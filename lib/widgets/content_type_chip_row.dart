import 'package:flutter/material.dart';
import '../models/series.dart';
import '../theme/app_theme.dart';

/// Horizontal scrollable content-type filter — "All" plus every entry
/// in kContentTypeLabels — used above the Browse grid, alongside
/// GenreChipRow, so a title-heavy browse ("Movies", "Series") doesn't
/// get lost in an all-types grid that used to only ever be dramas.
class ContentTypeChipRow extends StatelessWidget {
  static const all = 'All';

  final String selected;
  final ValueChanged<String> onSelect;

  const ContentTypeChipRow({super.key, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final types = [all, ...kContentTypeLabels.keys];
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: types.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (ctx, i) {
          final type = types[i];
          final label = type == all ? all : kContentTypeLabels[type]!;
          final isSelected = type == selected;
          return GestureDetector(
            onTap: () => onSelect(type),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isSelected ? AppColors.secondary.withOpacity(0.18) : AppColors.surface,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: isSelected ? AppColors.secondary : AppColors.surfaceBorder),
              ),
              child: Text(
                label,
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
