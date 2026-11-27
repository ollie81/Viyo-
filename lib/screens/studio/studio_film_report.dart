import 'package:flutter/material.dart';

import '../../services/creator_studio_service.dart';
import '../../theme/app_theme.dart';
import 'studio_widgets.dart';

/// Opens the free whole-film report for a production.
Future<void> showFilmReport(BuildContext context, String projectId) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: StudioColors.panel,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (_, scroll) => FutureBuilder<Map<String, dynamic>>(
        future: CreatorStudioService.filmReport(projectId),
        builder: (_, snap) {
          if (snap.hasError) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Couldn\'t load the report: ${snap.error}', style: const TextStyle(color: AppColors.danger)),
            );
          }
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          return FilmReportView(report: snap.data!, controller: scroll);
        },
      ),
    ),
  );
}

/// The whole-film report: what's wrong, where, and how to fix it. Nothing is remade from here.
class FilmReportView extends StatefulWidget {
  final Map<String, dynamic> report;
  final ScrollController? controller;
  const FilmReportView({super.key, required this.report, this.controller});

  @override
  State<FilmReportView> createState() => _FilmReportViewState();
}

class _FilmReportViewState extends State<FilmReportView> {
  String? filter;

  static const _statusColor = {'ok': AppColors.success, 'attention': AppColors.coin, 'problem': AppColors.danger};
  static const _statusText = {'ok': 'OK', 'attention': 'Look at', 'problem': 'Problem', 'not_checked': 'After render'};
  static const _sevColor = {'high': AppColors.danger, 'medium': AppColors.coin, 'low': AppColors.textMuted};

  @override
  Widget build(BuildContext context) {
    final r = widget.report;
    final cats = ((r['categories'] as List?) ?? const []).cast<Map>();
    final problems = ((r['problems'] as List?) ?? const []).cast<Map>();
    final shown = filter == null ? problems : problems.where((p) => p['category'] == filter).toList();
    final notes = ((r['notes'] as List?) ?? const []).map((e) => '$e').toList();
    final render = r['render'] as Map?;
    return ListView(controller: widget.controller, padding: const EdgeInsets.fromLTRB(18, 14, 18, 28), children: [
      Center(
        child: Container(width: 36, height: 4, decoration: BoxDecoration(color: AppColors.textMuted, borderRadius: BorderRadius.circular(2))),
      ),
      const SizedBox(height: 14),
      const Text('Film report', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
      const SizedBox(height: 4),
      Text(render == null ? 'Reviews the plan and what\'s made so far.' : 'Version ${render['version']} of your film.',
          style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
      const SizedBox(height: 10),
      Text('${r['summary'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final c in cats)
          FilterChip(
            selected: filter == c['key'],
            onSelected: (v) => setState(() => filter = v ? '${c['key']}' : null),
            avatar: Icon(Icons.circle, size: 10, color: _statusColor[c['status']] ?? AppColors.textMuted),
            label: Text('${c['label']} · ${(c['count'] as num?)?.toInt() == 0 ? _statusText[c['status']] ?? '' : c['count']}',
                style: const TextStyle(fontSize: 12)),
          ),
      ]),
      const SizedBox(height: 12),
      if (shown.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text('Nothing to fix here.', style: TextStyle(color: AppColors.success)),
        ),
      for (final p in shown) _problem(p),
      for (final n in notes)
        Padding(padding: const EdgeInsets.only(top: 6), child: Text(n, style: const TextStyle(color: AppColors.textMuted, fontSize: 12))),
      const SizedBox(height: 10),
      Text('${r['note'] ?? ''}', style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5, height: 1.4)),
    ]);
  }

  Widget _problem(Map p) {
    final where = [if (p['scene'] != null) 'Scene ${p['scene']}', if (p['shot'] != null) 'shot ${p['shot']}'].join(', ');
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: studioPanel(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.circle, size: 9, color: _sevColor[p['severity']] ?? AppColors.textMuted),
          const SizedBox(width: 6),
          Expanded(
            child: Text(where.isEmpty ? 'Whole film' : where,
                style: const TextStyle(fontSize: 12, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
          ),
        ]),
        const SizedBox(height: 6),
        Text('${p['problem']}', style: const TextStyle(fontSize: 13.5, height: 1.35)),
        const SizedBox(height: 4),
        Text('Fix: ${p['fix']}', style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.35)),
        const SizedBox(height: 4),
        Text('${p['route_label'] ?? ''}', style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
      ]),
    );
  }
}
