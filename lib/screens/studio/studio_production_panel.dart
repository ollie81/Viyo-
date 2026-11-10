import 'package:flutter/material.dart';

import '../../services/creator_studio_service.dart';
import '../../theme/app_theme.dart';
import 'studio_widgets.dart';

/// One-click production: see everything still needed and the full price,
/// reserve it once, then follow the progress while Viyo makes the film.
class ProductionPanel extends StatefulWidget {
  final StudioProjectDetail d;
  final Future<void> Function() reload;
  final Future<void> Function() onNeedCredits;
  const ProductionPanel({super.key, required this.d, required this.reload, required this.onNeedCredits});

  @override
  State<ProductionPanel> createState() => _ProductionPanelState();
}

class _ProductionPanelState extends State<ProductionPanel> {
  bool _working = false;

  Map<String, dynamic>? get _run => widget.d.production;

  Future<void> _start() async {
    var sheets = true;
    Map<String, dynamic> q;
    setState(() => _working = true);
    try {
      q = await CreatorStudioService.productionQuote(widget.d.project.id, sheets: sheets);
    } on StudioException catch (e) {
      if (mounted) showStudioError(context, e.message);
      return;
    } finally {
      if (mounted) setState(() => _working = false);
    }
    if (!mounted) return;
    final go = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDialog) {
        final stages = (q['stages'] as List?) ?? [];
        final blocked = ((q['blocked'] as List?) ?? []).map((e) => '$e').toList();
        final total = (q['total_credits'] as num?)?.toInt() ?? 0;
        final available = ((q['balance'] as Map?)?['available'] as num?)?.toInt() ?? 0;
        final short = total > available;
        return AlertDialog(
          backgroundColor: StudioColors.panel,
          title: const Text('Make the whole film'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Text('Viyo makes everything still missing, in order, then puts the film together. You can close the app; '
                    'it keeps working.', style: TextStyle(color: AppColors.textMuted, fontSize: 12.5, height: 1.4)),
                const SizedBox(height: 12),
                for (final s in stages)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      Expanded(child: Text('${s['label']} (${(s['items'] as List).length})')),
                      Text(creditsLabel((s['credits'] as num).toInt()), style: const TextStyle(fontWeight: FontWeight.w600)),
                    ]),
                  ),
                const Divider(height: 20),
                Row(children: [
                  const Expanded(child: Text('Total', style: TextStyle(fontWeight: FontWeight.w800))),
                  Text(creditsLabel(total), style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.coin, fontSize: 16)),
                ]),
                const SizedBox(height: 4),
                Text('Your balance: ${creditsLabel(available)}', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                const SizedBox(height: 10),
                Text('${q['note'] ?? ''}', style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5, height: 1.35)),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: sheets,
                  title: const Text('Character reference sheets', style: TextStyle(fontSize: 13.5)),
                  subtitle: const Text('Keeps every character the same person in every scene (recommended).',
                      style: TextStyle(fontSize: 11.5)),
                  onChanged: (v) async {
                    try {
                      final nq = await CreatorStudioService.productionQuote(widget.d.project.id, sheets: v);
                      setDialog(() {
                        sheets = v;
                        q = nq;
                      });
                    } on StudioException catch (e) {
                      if (ctx.mounted) showStudioError(ctx, e.message);
                    }
                  },
                ),
                if (blocked.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text('Fix these first:\n• ${blocked.take(5).join('\n• ')}',
                      style: const TextStyle(color: AppColors.danger, fontSize: 12.5, height: 1.4)),
                ],
                if (stages.isEmpty && blocked.isEmpty)
                  const Text('Everything is already made.', style: TextStyle(color: AppColors.success)),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            if (short && blocked.isEmpty && stages.isNotEmpty)
              FilledButton(onPressed: () => Navigator.pop(ctx, {'credits': true}), child: const Text('Get credits'))
            else
              FilledButton(
                onPressed: blocked.isNotEmpty || stages.isEmpty
                    ? null
                    : () => Navigator.pop(ctx, {'total': total, 'sheets': sheets}),
                child: Text('Reserve ${creditsLabel(total)} & start'),
              ),
          ],
        );
      }),
    );
    if (go == null || !mounted) return;
    if (go['credits'] == true) {
      await widget.onNeedCredits();
      return;
    }
    setState(() => _working = true);
    try {
      await CreatorStudioService.startProduction(widget.d.project.id,
          confirmCredits: go['total'] as int, sheets: go['sheets'] as bool);
      await widget.reload();
      if (mounted) showStudioInfo(context, 'Production started. You can close the app; it keeps working.');
    } on StudioException catch (e) {
      if (!mounted) return;
      if (e.status == 402) {
        await widget.onNeedCredits();
      } else {
        showStudioError(context, e.message);
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _act(Future<void> Function() action, String done) async {
    setState(() => _working = true);
    try {
      await action();
      await widget.reload();
      if (mounted) showStudioInfo(context, done);
    } on StudioException catch (e) {
      if (mounted) showStudioError(context, e.message);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final run = _run;
    final status = run?['status'] as String?;
    final active = status == 'running' || status == 'needs_attention';
    return Container(
      decoration: studioPanel(border: active ? AppColors.primary.withValues(alpha: 0.35) : null),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Icons.movie_creation_outlined, color: AppColors.primary, size: 20),
          const SizedBox(width: 8),
          const Expanded(child: Text('Make the whole film', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
          if (!active)
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.black),
              onPressed: _working ? null : _start,
              child: Text(_working ? 'Checking…' : 'See price'),
            ),
        ]),
        const SizedBox(height: 4),
        if (!active)
          Text(
            status == 'done'
                ? 'Last production finished. Change anything and run it again: only what\'s missing is made.'
                : 'One price for everything still missing: character sheets, pictures, voices, videos and the final film.',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.35),
          ),
        if (active) ..._progress(run!),
      ]),
    );
  }

  List<Widget> _progress(Map<String, dynamic> run) {
    final percent = ((run['percent'] as num?) ?? 0).toInt();
    final stages = (run['stages'] as List?) ?? [];
    final waiting = run['status'] == 'needs_attention';
    return [
      const SizedBox(height: 8),
      ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: LinearProgressIndicator(value: percent / 100, minHeight: 8),
      ),
      const SizedBox(height: 6),
      Text('$percent% · spent ${creditsLabel((run['spent_credits'] as num?)?.toInt() ?? 0)} of '
          '${creditsLabel((run['quoted_credits'] as num?)?.toInt() ?? 0)} reserved',
          style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
      const SizedBox(height: 10),
      for (final s in stages)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Icon(
              s['done'] == s['total']
                  ? Icons.check_circle
                  : (s['working'] as num) > 0
                      ? Icons.autorenew
                      : Icons.radio_button_unchecked,
              size: 16,
              color: s['done'] == s['total'] ? AppColors.success : AppColors.textMuted,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text('${s['label']}', style: const TextStyle(fontSize: 13))),
            Text('${s['done']}/${s['total']}', style: const TextStyle(fontSize: 12.5, fontFeatures: [FontFeature.tabularFigures()])),
            if ((s['failed'] as num) > 0)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text('${s['failed']} retried', style: const TextStyle(color: AppColors.coin, fontSize: 11.5)),
              ),
          ]),
        ),
      if (waiting) ...[
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.coin.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.coin.withValues(alpha: 0.35)),
          ),
          child: Text('Paused. ${run['problem'] ?? ''}\nFix it (or redo that scene yourself), then resume. Nothing already made is redone.',
              style: const TextStyle(fontSize: 12.5, height: 1.4)),
        ),
      ],
      const SizedBox(height: 10),
      Wrap(spacing: 8, children: [
        if (waiting)
          FilledButton(
            onPressed: _working
                ? null
                : () => _act(() => CreatorStudioService.resumeProduction('${run['id']}'), 'Production resumed.'),
            child: const Text('Resume'),
          ),
        TextButton(
          onPressed: _working
              ? null
              : () async {
                  final yes = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: StudioColors.panel,
                      title: const Text('Stop this production?'),
                      content: const Text('Steps not started yet are canceled and the rest of the reserved credits come back. '
                          'Everything already made is kept.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep going')),
                        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Stop')),
                      ],
                    ),
                  );
                  if (yes == true) {
                    await _act(() => CreatorStudioService.cancelProduction('${run['id']}'), 'Production stopped.');
                  }
                },
          child: const Text('Stop'),
        ),
      ]),
    ];
  }
}
