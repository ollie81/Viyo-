import 'package:flutter/material.dart';

import '../../services/creator_studio_service.dart';
import '../../theme/app_theme.dart';
import 'studio_widgets.dart';

/// The film's planned score: one cue per stretch of story, planned silences, character themes and what new cues
/// add to the render. Read-only and free.
class StudioScoreCard extends StatefulWidget {
  final String projectId;
  final Future<Map<String, dynamic>> Function(String id)? load;
  const StudioScoreCard({super.key, required this.projectId, this.load});

  @override
  State<StudioScoreCard> createState() => _StudioScoreCardState();
}

class _StudioScoreCardState extends State<StudioScoreCard> {
  Map<String, dynamic>? s;

  static const moods = {
    'action': 'Action',
    'tension': 'Tension',
    'dread': 'Dread',
    'mystery': 'Mystery',
    'tender': 'Tender',
    'emotional': 'Emotional',
    'aftermath': 'Aftermath',
    'light': 'Light',
    'reflective': 'Reflective',
    'finale': 'Finale',
    'silence': 'Silence',
  };

  @override
  void initState() {
    super.initState();
    (widget.load ?? CreatorStudioService.score)(widget.projectId).then((v) {
      if (mounted) setState(() => s = v);
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final d = s;
    if (d == null) return const SizedBox.shrink();
    final cues = ((d['cues'] as List?) ?? const []).cast<Map>();
    final themes = Map<String, dynamic>.from(d['themes'] as Map? ?? const {});
    final enabled = d['enabled'] == true;
    final newCues = (d['new_cues'] as num?)?.toInt() ?? 0;
    return Container(
      decoration: studioPanel(),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Icons.music_note_outlined, size: 18, color: AppColors.coin),
          const SizedBox(width: 8),
          const Expanded(child: Text('Score', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5))),
          if (enabled && newCues > 0)
            Text('$newCues new · ${creditsLabel((d['music_credits'] as num?)?.toInt() ?? 0)}',
                style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
        ]),
        const SizedBox(height: 6),
        if (!enabled)
          Text(d['uses'] == 'your music' ? 'Your own music plays under the film.' : 'Music is off for this film.',
              style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted))
        else ...[
          for (final c in cues)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(
                  width: 92,
                  child: Text(moods['${c['mood']}'] ?? '${c['mood']}',
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: c['silent'] == true ? AppColors.textMuted : AppColors.textPrimary)),
                ),
                Expanded(
                  child: Text(
                    'Scene${((c['positions'] as List?) ?? const []).length == 1 ? '' : 's'} '
                    '${((c['positions'] as List?) ?? const []).join(', ')} · ${((c['seconds'] as num?) ?? 0).round()} s'
                    '${c['silent'] == true ? ' · planned silence' : c['status'] == 'made' ? ' · made' : ' · new'}',
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ),
              ]),
            ),
          if (themes.isNotEmpty) ...[
            const SizedBox(height: 4),
            for (final e in themes.entries)
              Text('${e.key}\'s theme: ${e.value}', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ],
          const SizedBox(height: 6),
          Text('${d['note'] ?? ''}', style: const TextStyle(fontSize: 11, color: AppColors.textMuted, height: 1.35)),
        ],
      ]),
    );
  }
}
