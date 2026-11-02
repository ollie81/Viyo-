import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Renders one set of Glow Up suggestions. Used right after a run and when
/// reopening a saved Glow Up.
class GlowUpResultsView extends StatelessWidget {
  final Map<String, dynamic> result;

  const GlowUpResultsView({super.key, required this.result});

  List<Map<String, dynamic>> _list(String key) =>
      ((result[key] as List<dynamic>?) ?? const []).whereType<Map<String, dynamic>>().toList();

  List<String> _strings(String key) =>
      ((result[key] as List<dynamic>?) ?? const []).map((e) => e.toString()).toList();

  @override
  Widget build(BuildContext context) {
    final summary = (result['summary'] as String?) ?? '';
    final nextStep = (result['next_step'] as String?) ?? '';
    final photoNote = result['photo_note'] as String?;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (summary.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: AppTheme.glowCard(glowColor: AppColors.secondary, gradient: AppGradients.primary, glowOpacity: 0.2),
            child: Text(summary, style: const TextStyle(fontSize: 15, height: 1.45, fontWeight: FontWeight.w600)),
          ),
        if (photoNote != null && photoNote.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Note: $photoNote', style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
        ],
        const SizedBox(height: 18),
        const _Section(icon: Icons.content_cut, color: AppColors.primary, title: 'Hairstyles to try'),
        for (final h in _list('hair'))
          _Card(
            title: (h['name'] ?? '').toString(),
            body: (h['why'] ?? '').toString(),
            footer: (h['how_to_ask'] ?? '').toString().isEmpty ? null : 'Ask for: ${h['how_to_ask']}',
          ),
        const SizedBox(height: 14),
        const _Section(icon: Icons.spa_outlined, color: AppColors.success, title: 'Grooming'),
        _Bullets(items: _strings('grooming')),
        const SizedBox(height: 14),
        const _Section(icon: Icons.checkroom, color: AppColors.secondary, title: 'Style'),
        for (final s in _list('style'))
          _Card(title: (s['item'] ?? '').toString(), body: (s['why'] ?? '').toString()),
        const SizedBox(height: 14),
        const _Section(icon: Icons.palette_outlined, color: AppColors.coin, title: 'Colours to try'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _strings('colors')
              .map((c) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: AppColors.surfaceBorder),
                    ),
                    child: Text(c, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                  ))
              .toList(),
        ),
        if (nextStep.isNotEmpty) ...[
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: AppTheme.card(borderColor: AppColors.primary.withOpacity(0.5)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.flag_outlined, color: AppColors.primary, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Try this week',
                          style: TextStyle(fontSize: 11, color: AppColors.textMuted, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text(nextStep, style: const TextStyle(fontSize: 13.5, height: 1.4)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 14),
        const Text(
          'These are AI suggestions to try, not a judgment of you. Your stylist or barber knows your hair best.',
          style: TextStyle(fontSize: 11, color: AppColors.textMuted, height: 1.4),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;

  const _Section({required this.icon, required this.color, required this.title});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        ]),
      );
}

class _Card extends StatelessWidget {
  final String title;
  final String body;
  final String? footer;

  const _Card({required this.title, required this.body, this.footer});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(13),
        decoration: AppTheme.card(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            if (body.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(body, style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.4)),
            ],
            if (footer != null) ...[
              const SizedBox(height: 6),
              Text(footer!, style: const TextStyle(fontSize: 12, color: AppColors.primary, height: 1.35)),
            ],
          ],
        ),
      );
}

class _Bullets extends StatelessWidget {
  final List<String> items;

  const _Bullets({required this.items});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(13),
        decoration: AppTheme.card(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final t in items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('•  ', style: TextStyle(color: AppColors.success)),
                    Expanded(child: Text(t, style: const TextStyle(fontSize: 13, height: 1.4))),
                  ],
                ),
              ),
          ],
        ),
      );
}
