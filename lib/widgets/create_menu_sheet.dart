import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// What the creator picked from the "+" menu. Callers decide what each
/// choice actually navigates to — this sheet only presents the choice.
enum CreateMenuChoice { photoVideo, aiDrama, challenge }

/// The "+" tab used to jump straight to CreatePostScreen. Now it opens
/// this menu first — a normal upload and an AI Short Drama upload are
/// different enough flows (a drama always needs a series + episode
/// number, see UploadAiDramaScreen) that picking one up front reads
/// better than folding both into one screen with a mode switch.
Future<CreateMenuChoice?> showCreateMenuSheet(BuildContext context) {
  return showModalBottomSheet<CreateMenuChoice>(
    context: context,
    backgroundColor: AppColors.background,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: AppColors.surfaceBorder,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Create', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(height: 14),
            _CreateMenuTile(
              icon: Icons.add_photo_alternate_outlined,
              iconColor: AppColors.primary,
              title: 'Upload Photo / Video',
              subtitle: 'Share a photo, video, or text post',
              onTap: () => Navigator.of(ctx).pop(CreateMenuChoice.photoVideo),
            ),
            const SizedBox(height: 10),
            // Visually highlighted — a sparkle icon and a glowing
            // secondary-color border, since AI Short Dramas are the
            // feature this menu exists to spotlight.
            _CreateMenuTile(
              icon: Icons.auto_awesome,
              iconColor: AppColors.secondary,
              title: 'Upload Short Drama',
              subtitle: 'Add an episode to a series',
              highlighted: true,
              onTap: () => Navigator.of(ctx).pop(CreateMenuChoice.aiDrama),
            ),
            const SizedBox(height: 10),
            _CreateMenuTile(
              icon: Icons.emoji_events_outlined,
              iconColor: AppColors.coin,
              title: 'Create / Join Challenge',
              subtitle: 'Take part in a creator mission',
              onTap: () => Navigator.of(ctx).pop(CreateMenuChoice.challenge),
            ),
          ],
        ),
      ),
    ),
  );
}

class _CreateMenuTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool highlighted;
  final VoidCallback onTap;

  const _CreateMenuTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: highlighted ? iconColor.withOpacity(0.10) : AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: highlighted ? iconColor.withOpacity(0.55) : AppColors.surfaceBorder,
            width: highlighted ? 1.4 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                      if (highlighted) ...[
                        const SizedBox(width: 6),
                        Icon(Icons.auto_awesome, size: 12, color: iconColor),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: AppColors.textMuted.withOpacity(0.6)),
          ],
        ),
      ),
    );
  }
}
