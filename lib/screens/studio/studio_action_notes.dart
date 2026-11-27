import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// An action shot's beat and movement, and any shot current video models struggle with, with a simpler
/// alternative. Shown in the shot plan, before anything is made.
class ShotActionNotes extends StatelessWidget {
  final Map<String, dynamic>? action;
  const ShotActionNotes({super.key, required this.action});

  static const beats = {
    'setup': 'Set-up',
    'escalation': 'Escalation',
    'reversal': 'Reversal',
    'climax': 'Climax',
    'consequence': 'Consequence',
  };

  @override
  Widget build(BuildContext context) {
    final a = action;
    if (a == null || a.isEmpty) return const SizedBox.shrink();
    final beat = beats['${a['beat'] ?? ''}'];
    final move = '${a['movement_direction'] ?? ''}'.replaceAll('_', ' ');
    final env = '${a['environment_change'] ?? ''}';
    final flags = ((a['feasibility'] as List?) ?? const []).cast<Map>();
    final line = [if (beat != null) beat, if (move.isNotEmpty && move != 'none') 'moving $move', if (env.isNotEmpty) env];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (line.isNotEmpty)
        Text(line.join(' · '), style: const TextStyle(fontSize: 11.5, color: AppColors.coin, fontWeight: FontWeight.w600)),
      for (final f in flags)
        Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.warning_amber_rounded, size: 14, color: f['risk'] == 'high' ? AppColors.danger : AppColors.coin),
            const SizedBox(width: 4),
            Expanded(
              child: Text('${f['issue']} Simpler: ${f['alternative']}',
                  style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, height: 1.3)),
            ),
          ]),
        ),
    ]);
  }
}
