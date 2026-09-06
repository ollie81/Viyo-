import 'package:flutter/material.dart';
import '../services/moderation_service.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';

/// Bottom sheet for reporting a post or a user. Tapping a reason submits
/// immediately — "Other" prompts for a short free-text reason first.
/// Reports are only ever readable by the app operator (RLS blocks
/// everyone else, reporter included), so there's no "view my reports"
/// screen to build here.
Future<void> showReportSheet(
  BuildContext context, {
  required String targetType, // 'post' or 'user'
  required String targetId,
}) async {
  final reason = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: AppColors.surface,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                targetType == 'post' ? 'Report post' : 'Report user',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          ...ModerationService.reportReasons.map(
            (r) => ListTile(
              title: Text(r),
              onTap: () => Navigator.pop(ctx, r),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );

  if (reason == null || !context.mounted) return;

  String? details;
  if (reason == 'Other') {
    final controller = TextEditingController();
    details = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tell us more'),
        content: TextField(
          controller: controller,
          maxLength: 300,
          maxLines: 3,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'What happened?'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
    if (details == null || !context.mounted) return;
  }

  final reporterId = SupabaseService.currentUserId;
  if (reporterId == null) return;

  try {
    await ModerationService.submitReport(
      reporterId: reporterId,
      targetType: targetType,
      targetId: targetId,
      reason: reason,
      details: details?.isEmpty == true ? null : details,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Thanks — we've received your report.")),
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Could not submit report: $e')),
    );
  }
}
