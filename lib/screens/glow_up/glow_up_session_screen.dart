import 'package:flutter/material.dart';

import '../../services/glow_up_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/friendly_error.dart';
import 'glow_up_results_view.dart';

/// One saved Glow Up, loaded from the server (so it survives refreshes and
/// sign-out/sign-in). Shows the saved photo through a fresh private link when
/// the user chose to save it; otherwise says plainly that no photo was kept.
class GlowUpSessionScreen extends StatefulWidget {
  final String sessionId;

  const GlowUpSessionScreen({super.key, required this.sessionId});

  @override
  State<GlowUpSessionScreen> createState() => _GlowUpSessionScreenState();
}

class _GlowUpSessionScreenState extends State<GlowUpSessionScreen> {
  Map<String, dynamic>? _session;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await GlowUpService.session(widget.sessionId);
      if (mounted) setState(() => _session = s);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyErrorMessage(e));
    }
  }

  Future<bool> _confirm(String title, String body, String action) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: Text(action)),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _deletePhoto() async {
    if (!await _confirm('Delete this photo?', 'The photo is removed for good. Your ideas stay saved.', 'Delete photo')) {
      return;
    }
    setState(() => _busy = true);
    try {
      await GlowUpService.deletePhoto(widget.sessionId);
      await _load();
      _snack('Photo deleted.');
    } catch (e) {
      _snack(friendlyErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteSession() async {
    if (!await _confirm('Delete this Glow Up?',
        'The ideas and the saved photo (if any) are removed for good.', 'Delete')) {
      return;
    }
    setState(() => _busy = true);
    try {
      await GlowUpService.deleteSession(widget.sessionId);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      _snack(friendlyErrorMessage(e));
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    final s = _session;
    final goal = GlowUpService.styleGoals[s?['style_goal']] ?? 'Glow Up';
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(s == null ? 'Glow Up' : goal),
        actions: [
          if (s != null)
            IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete_outline), onPressed: _busy ? null : _deleteSession),
        ],
      ),
      body: _error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
          : s == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  children: [
                    GlowUpPhotoHeader(
                      photo: s['photo_url'] != null
                          ? Image.network(s['photo_url'] as String, fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image_outlined)))
                          : null,
                      caption: s['has_photo'] == true
                          ? 'Saved privately. Only you can see it.'
                          : 'Photo not saved for this Glow Up.',
                      details: [
                        GlowUpService.styleGoals[s['style_goal']] ?? '',
                        GlowUpService.presentations[s['presentation']] ?? '',
                        glowUpDate(s['created_at'] as String?),
                      ].where((x) => x.isNotEmpty).join(' · '),
                      onDeletePhoto: s['has_photo'] == true && !_busy ? _deletePhoto : null,
                    ),
                    const SizedBox(height: 16),
                    GlowUpResultsView(result: (s['recommendations'] as Map).cast<String, dynamic>()),
                  ],
                ),
    );
  }
}

String glowUpDate(String? iso) {
  final d = DateTime.tryParse(iso ?? '')?.toLocal();
  if (d == null) return '';
  return '${d.day}/${d.month}/${d.year}';
}

/// The photo a Glow Up was made from, with what was chosen and when.
class GlowUpPhotoHeader extends StatelessWidget {
  final Widget? photo;
  final String caption;
  final String details;
  final VoidCallback? onDeletePhoto;

  const GlowUpPhotoHeader({
    super.key,
    required this.photo,
    required this.caption,
    required this.details,
    this.onDeletePhoto,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: AppTheme.card(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 96,
              height: 128,
              color: AppColors.surfaceBorder,
              child: photo ?? const Icon(Icons.no_photography_outlined, color: AppColors.textMuted),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Your photo', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(caption, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.35)),
                if (details.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(details, style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
                ],
                if (onDeletePhoto != null) ...[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                    onPressed: onDeletePhoto,
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: const Text('Delete photo'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
