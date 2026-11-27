import 'package:flutter/material.dart';

import '../../services/creator_studio_service.dart';
import '../../theme/app_theme.dart';
import 'studio_checkout_screen.dart';
import 'studio_widgets.dart';

/// "Make the whole film": the checkout (full estimate and rules) and then the production tracker: current, completed
/// and remaining stages, credits spent, refunded and still reserved, the remaining approved budget, the next step,
/// and the two moments the production waits for the creator (a budget increase, the storyboard review).
class ProductionPanel extends StatefulWidget {
  final StudioProjectDetail d;
  final Future<void> Function() reload;
  final Future<void> Function() onNeedCredits;
  const ProductionPanel({super.key, required this.d, required this.reload, required this.onNeedCredits});

  @override
  State<ProductionPanel> createState() => _ProductionPanelState();
}

const _activeStatuses = {'running', 'needs_attention', 'needs_approval', 'storyboard_review'};

class _ProductionPanelState extends State<ProductionPanel> {
  bool _working = false;

  Map<String, dynamic>? get _run => widget.d.production;
  int _i(Object? v) => (v as num?)?.toInt() ?? 0;

  Future<void> _start() async {
    Map<String, dynamic> q;
    setState(() => _working = true);
    try {
      q = await CreatorStudioService.productionQuote(widget.d.project.id);
    } on StudioException catch (e) {
      if (mounted) showStudioError(context, e.message);
      return;
    } finally {
      if (mounted) setState(() => _working = false);
    }
    if (!mounted) return;
    final go = await Navigator.of(context).push<Map<String, dynamic>>(MaterialPageRoute(
      builder: (_) => ProductionCheckoutScreen(
        quote: q,
        requote: ({required bool sheets, required bool direct}) =>
            CreatorStudioService.productionQuote(widget.d.project.id, sheets: sheets, direct: direct),
      ),
    ));
    if (go == null || !mounted) return;
    if (go['plan_shots'] is List) {
      await confirmAndRun(context,
          projectId: widget.d.project.id,
          kind: 'shotplan',
          targets: (go['plan_shots'] as List).cast<String>(),
          title: 'Plan camera shots',
          extraWarning: 'Then check and approve each scene\'s shot plan on the Scenes tab before making the film.',
          onStarted: (_) => widget.reload(),
          onNeedCredits: () => widget.onNeedCredits());
      return;
    }
    if (go['credits'] == true) {
      await widget.onNeedCredits();
      return;
    }
    setState(() => _working = true);
    try {
      await CreatorStudioService.startProduction(widget.d.project.id,
          confirmCredits: go['total'] as int,
          sheets: go['sheets'] as bool,
          direct: go['direct'] as bool,
          storyboardReview: go['storyboard'] as bool);
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
      if (!mounted) return;
      if (e.status == 402) {
        showStudioError(context, e.message);
        await widget.onNeedCredits();
      } else {
        showStudioError(context, e.message);
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _approveIncrease(Map<String, dynamic> run) async {
    final extra = _i(run['needs_credits']);
    final approved = _i(run['approved_credits']);
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: StudioColors.panel,
        title: const Text('Approve more credits?'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${run['problem'] ?? ''}', style: const TextStyle(height: 1.4)),
            const SizedBox(height: 10),
            Text('Extra: ${creditsLabel(extra)}\nNew maximum: ${creditsLabel(approved + extra)}',
                style: const TextStyle(fontWeight: FontWeight.w700, height: 1.5)),
            const SizedBox(height: 6),
            const Text('It\'s reserved from your balance now. Unused credits come back at the end. Nothing is bought '
                'automatically.', style: TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.4)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Not now')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Approve ${creditsLabel(extra)}')),
        ],
      ),
    );
    if (yes == true) {
      await _act(() => CreatorStudioService.approveProductionBudget('${run['id']}', extra), 'Approved. Production continues.');
    }
  }

  Future<void> _approveStoryboard(Map<String, dynamic> run) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: StudioColors.panel,
        title: const Text('Approve the storyboard?'),
        content: const Text('Video clips are made from these pictures. Check the characters, framing, actions, camera '
            'directions and scene details on the Scenes tab first. You can report a defect (free check) or remake a '
            'picture before approving.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep reviewing')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Approve & make video')),
        ],
      ),
    );
    if (yes == true) {
      await _act(() => CreatorStudioService.approveStoryboard('${run['id']}'), 'Storyboard approved. Video is being made.');
    }
  }

  Future<void> _history(Map<String, dynamic> run) async {
    Map<String, dynamic> h;
    try {
      h = await CreatorStudioService.productionHistory('${run['id']}');
    } on StudioException catch (e) {
      if (mounted) showStudioError(context, e.message);
      return;
    }
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (_) => ProductionHistorySheet(history: h),
    );
  }

  @override
  Widget build(BuildContext context) {
    final run = _run;
    final status = run?['status'] as String?;
    final active = _activeStatuses.contains(status);
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
              child: Text(_working ? 'Checking…' : 'See full price'),
            ),
        ]),
        const SizedBox(height: 4),
        if (!active)
          Text(
            status == 'done'
                ? 'Last production finished. Change anything and run it again: only what\'s missing is made.'
                : 'See the complete cost first: every part, the most it can cost, what happens if something fails, '
                    'revisions, and publishing.',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.35),
          ),
        if (run != null && !active && (status == 'done' || status == 'canceled'))
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(onPressed: () => _history(run), child: const Text('Where the credits went')),
          ),
        if (active) ...ProductionTracker.build(
          run: run!,
          working: _working,
          onResume: () => _act(() => CreatorStudioService.resumeProduction('${run['id']}'), 'Production resumed.'),
          onApproveBudget: () => _approveIncrease(run),
          onApproveStoryboard: () => _approveStoryboard(run),
          onHistory: () => _history(run),
          onStop: () async {
            final yes = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor: StudioColors.panel,
                title: const Text('Stop this production?'),
                content: const Text('Steps not started yet are canceled and the rest of the reserved credits come '
                    'back. Everything already made is kept.'),
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
        ),
      ]),
    );
  }
}

/// The tracker itself (a pure function of the run, so it can be tested on its own).
class ProductionTracker {
  static int _i(Object? v) => (v as num?)?.toInt() ?? 0;

  static List<Widget> build({
    required Map<String, dynamic> run,
    required bool working,
    required VoidCallback onResume,
    required VoidCallback onApproveBudget,
    required VoidCallback onApproveStoryboard,
    required VoidCallback onHistory,
    required VoidCallback onStop,
  }) {
    final percent = _i(run['percent']);
    final stages = (run['stages'] as List?) ?? [];
    final status = run['status'] as String?;
    final approved = _i(run['approved_credits'] ?? run['quoted_credits']);
    String statusLabel() => switch (status) {
          'needs_approval' => 'Waiting for your approval (budget)',
          'storyboard_review' => 'Waiting for your storyboard review',
          'needs_attention' => 'Paused: needs you',
          _ => 'Making your film',
        };
    return [
      const SizedBox(height: 8),
      Text(statusLabel(), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
      const SizedBox(height: 6),
      ClipRRect(borderRadius: BorderRadius.circular(6), child: LinearProgressIndicator(value: percent / 100, minHeight: 8)),
      const SizedBox(height: 8),
      _line('Approved budget', creditsLabel(approved)),
      _line('Spent so far', creditsLabel(_i(run['spent_credits']))),
      _line('Refunded (failed or cheaper steps)', creditsLabel(_i(run['refunded_credits']))),
      _line('Still reserved', creditsLabel(_i(run['reserved_left']))),
      _line('Left in your approved budget', creditsLabel(_i(run['remaining_budget'])), bold: true),
      if (run['next_step'] != null) _line('Next step', '${run['next_step']}'),
      const SizedBox(height: 8),
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
                child: Text('${s['failed']} retried (not charged)', style: const TextStyle(color: AppColors.coin, fontSize: 11.5)),
              ),
          ]),
        ),
      if (status == 'needs_approval')
        _card(
            '${run['problem'] ?? 'This production needs more credits than you approved.'}\n'
            'Extra: ${creditsLabel(_i(run['needs_credits']))} · new maximum ${creditsLabel(approved + _i(run['needs_credits']))}.'
            '\nNothing continues until you approve.',
            AppColors.coin),
      if (status == 'storyboard_review')
        _card('${run['problem'] ?? 'Review the storyboard on the Scenes tab, then approve it to start the video.'}',
            AppColors.primary),
      if (status == 'needs_attention')
        _card('Paused. ${run['problem'] ?? ''}\nFix it (or redo that scene yourself), then resume. Nothing already made '
            'is redone.', AppColors.coin),
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 6, children: [
        if (status == 'needs_approval')
          FilledButton(onPressed: working ? null : onApproveBudget, child: const Text('Review & approve credits')),
        if (status == 'storyboard_review')
          FilledButton(onPressed: working ? null : onApproveStoryboard, child: const Text('Approve storyboard')),
        if (status == 'needs_attention') FilledButton(onPressed: working ? null : onResume, child: const Text('Resume')),
        TextButton(onPressed: onHistory, child: const Text('Where the credits went')),
        TextButton(onPressed: working ? null : onStop, child: const Text('Stop')),
      ]),
    ];
  }

  static Widget _line(String a, String b, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Expanded(child: Text(a, style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5))),
          Text(b,
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()])),
        ]),
      );

  static Widget _card(String text, Color color) => Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Text(text, style: const TextStyle(fontSize: 12.5, height: 1.4)),
      );
}

/// Every credit of one production: the reservation and approved increases, each step's hold, charge and refund,
/// and what came back at the end.
class ProductionHistorySheet extends StatelessWidget {
  final Map<String, dynamic> history;
  const ProductionHistorySheet({super.key, required this.history});

  static int _i(Object? v) => (v as num?)?.toInt() ?? 0;

  static String _event(Map e) => switch (e['kind']) {
        'reserved' => 'Reserved (approved budget)',
        'increase_requested' => 'More credits requested',
        'increase_approved' => 'Increase approved and reserved',
        'returned' => 'Unused credits returned',
        'storyboard_review' => 'Paused for storyboard review',
        'storyboard_approved' => 'Storyboard approved',
        _ => '${e['kind']}',
      };

  @override
  Widget build(BuildContext context) {
    final t = Map<String, dynamic>.from(history['totals'] as Map? ?? const {});
    final events = (history['events'] as List?) ?? const [];
    final steps = (history['steps'] as List?) ?? const [];
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.8,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          const Text('Where the credits went', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          const SizedBox(height: 10),
          Wrap(spacing: 16, runSpacing: 6, children: [
            Text('Approved: ${creditsLabel(_i(t['approved']))}'),
            Text('Charged: ${creditsLabel(_i(t['charged']))}'),
            Text('Refunded: ${creditsLabel(_i(t['refunded']))}'),
            Text('Returned: ${creditsLabel(_i(t['returned']))}'),
          ]),
          const SizedBox(height: 14),
          for (final e in events)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(_event(e as Map)),
              subtitle: '${e['note'] ?? ''}'.isEmpty ? null : Text('${e['note']}'),
              trailing: _i(e['credits']) == 0 ? null : Text(creditsLabel(_i(e['credits']))),
            ),
          const Divider(),
          for (final s in steps)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text('${(s as Map)['label'] ?? s['stage']}${_i(s['try']) > 1 ? ' (try ${s['try']})' : ''}'),
              subtitle: Text(s['status'] == 'failed'
                  ? 'Failed: not charged, ${creditsLabel(_i(s['refunded']))} refunded'
                  : s['status'] == 'succeeded'
                      ? 'Charged ${creditsLabel(_i(s['charged']))}'
                          '${_i(s['refunded']) > 0 ? ' · ${creditsLabel(_i(s['refunded']))} refunded' : ''}'
                      : '${s['status']} · ${creditsLabel(_i(s['held']))} held'),
            ),
        ]),
      ),
    );
  }
}
