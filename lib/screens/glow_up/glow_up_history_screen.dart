import 'package:flutter/material.dart';

import '../../services/glow_up_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/friendly_error.dart';
import 'glow_up_session_screen.dart';

/// Saved Glow Ups, loaded from the server for the signed-in user. Each can be
/// reopened or deleted (with its saved photo, if any); everything can be
/// deleted at once.
class GlowUpHistoryScreen extends StatefulWidget {
  const GlowUpHistoryScreen({super.key});

  @override
  State<GlowUpHistoryScreen> createState() => _GlowUpHistoryScreenState();
}

class _GlowUpHistoryScreenState extends State<GlowUpHistoryScreen> {
  List<Map<String, dynamic>>? _sessions;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await GlowUpService.sessions();
      if (mounted) setState(() => _sessions = s);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyErrorMessage(e));
    }
  }

  Future<void> _delete(String id) async {
    try {
      await GlowUpService.deleteSession(id);
      setState(() => _sessions = _sessions?.where((s) => s['id'] != id).toList());
    } catch (e) {
      _snack('Could not delete: ${friendlyErrorMessage(e)}');
    }
  }

  Future<void> _deleteAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Delete all Glow Ups?'),
        content: const Text('Every saved set of ideas and every saved photo will be removed. This can\'t be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete all')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await GlowUpService.deleteAll();
      setState(() => _sessions = []);
      _snack('All Glow Ups deleted.');
    } catch (e) {
      _snack('Could not delete: ${friendlyErrorMessage(e)}');
    }
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  String _date(String? iso) {
    final d = DateTime.tryParse(iso ?? '')?.toLocal();
    if (d == null) return '';
    return '${d.day}/${d.month}/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final sessions = _sessions;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('My Glow Ups'),
        actions: [
          if (sessions != null && sessions.isNotEmpty)
            IconButton(tooltip: 'Delete all', icon: const Icon(Icons.delete_sweep_outlined), onPressed: _deleteAll),
        ],
      ),
      body: _error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
          : sessions == null
              ? const Center(child: CircularProgressIndicator())
              : sessions.isEmpty
                  ? const Center(
                      child: Text('No saved Glow Ups yet.', style: TextStyle(color: AppColors.textSecondary)))
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: sessions.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final s = sessions[i];
                        final rec = (s['recommendations'] as Map?)?.cast<String, dynamic>() ?? const {};
                        final goal = GlowUpService.styleGoals[s['style_goal']] ?? 'Glow Up';
                        final direction = GlowUpService.presentations[s['presentation']];
                        final photoUrl = s['photo_url'] as String?;
                        return Container(
                          decoration: AppTheme.card(),
                          child: ListTile(
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: SizedBox(
                                width: 40,
                                height: 52,
                                child: photoUrl != null
                                    ? Image.network(photoUrl, fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => const Icon(Icons.auto_awesome, color: AppColors.secondary))
                                    : Container(
                                        color: AppColors.surfaceBorder,
                                        child: const Icon(Icons.auto_awesome, color: AppColors.secondary, size: 20)),
                              ),
                            ),
                            title: Text(
                                [goal, if (direction != null && s['presentation'] != 'any') direction,
                                 _date(s['created_at'] as String?)].join(' · '),
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                            subtitle: Text((rec['summary'] ?? '').toString(),
                                maxLines: 2, overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                            trailing: IconButton(
                              tooltip: 'Delete',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _delete(s['id'] as String),
                            ),
                            onTap: () async {
                              await Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) => GlowUpSessionScreen(sessionId: s['id'] as String),
                              ));
                              _load();     // reflect deletions made inside
                            },
                          ),
                        );
                      },
                    ),
    );
  }
}
