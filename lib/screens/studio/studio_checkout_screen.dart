import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'studio_widgets.dart';

typedef Requote = Future<Map<String, dynamic>> Function({required bool sheets, required bool direct});

/// The production checkout: before paying, a creator sees what they're buying, how many episodes, the cost of every
/// part, the most it can cost (and its estimated credit value), what happens on failure, the revisions included,
/// and whether they can publish and export. Returns {'total', 'sheets', 'direct', 'storyboard'} to start,
/// {'plan_shots': [...]} or {'credits': true}, or null.
class ProductionCheckoutScreen extends StatefulWidget {
  final Map<String, dynamic> quote;
  final Requote requote;
  const ProductionCheckoutScreen({super.key, required this.quote, required this.requote});

  @override
  State<ProductionCheckoutScreen> createState() => _ProductionCheckoutScreenState();
}

class _ProductionCheckoutScreenState extends State<ProductionCheckoutScreen> {
  late Map<String, dynamic> q = widget.quote;
  bool sheets = true, direct = true, storyboard = true, busy = false;

  Map<String, dynamic> get est => Map<String, dynamic>.from(q['estimate'] as Map? ?? const {});
  Map<String, dynamic> get terms => Map<String, dynamic>.from(q['terms'] as Map? ?? const {});
  int _i(Object? v) => (v as num?)?.toInt() ?? 0;
  List<String> _list(Object? v) => ((v as List?) ?? const []).map((e) => '$e').toList();

  Future<void> _change({bool? s, bool? d}) async {
    setState(() => busy = true);
    try {
      final nq = await widget.requote(sheets: s ?? sheets, direct: d ?? direct);
      if (!mounted) return;
      setState(() {
        sheets = s ?? sheets;
        direct = d ?? direct;
        q = nq;
      });
    } catch (e) {
      if (mounted) showStudioError(context, '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _storyboardOff() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: StudioColors.panel,
        title: const Text('Skip the storyboard review?'),
        content: const Text('Video clips will be made right after the pictures, without stopping for you to check the '
            'characters, framing, actions and camera directions first. Video is the most expensive part.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep the review')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Skip it')),
        ],
      ),
    );
    if (yes == true && mounted) setState(() => storyboard = false);
  }

  @override
  Widget build(BuildContext context) {
    final stages = (q['stages'] as List?) ?? const [];
    final blocked = _list(q['blocked']);
    final total = _i(q['total_credits']);
    final available = _i((q['balance'] as Map?)?['available']);
    final short = total > available;
    final value = (terms['credit_value_usd'] as num?)?.toDouble() ?? 0.01;
    final paid = terms['last_purchase'] as Map?;
    final episodes = Map<String, dynamic>.from(est['episodes'] as Map? ?? const {});
    final canStart = !busy && blocked.isEmpty && stages.isNotEmpty;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(backgroundColor: AppColors.background, title: const Text('Make the whole film')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
            _section('What you\'re buying', [
              const Text('VIYO makes everything still missing, in order, then puts the film together. You can close the '
                  'app; it keeps working.', style: _muted),
              const SizedBox(height: 8),
              for (final s in stages)
                _row('${s['label']} (${(s['items'] as List).length})', creditsLabel(_i(s['credits']))),
              if (stages.isEmpty && blocked.isEmpty)
                const Text('Everything is already made.', style: TextStyle(color: AppColors.success)),
            ]),
            _section('Episodes', [
              Text('${_i(episodes['in_this_production']) == 0 ? 1 : _i(episodes['in_this_production'])} finished '
                  'episode (or film) from this production.', style: const TextStyle(fontWeight: FontWeight.w600)),
              if ('${episodes['note'] ?? ''}'.isNotEmpty) Text('${episodes['note']}', style: _muted),
            ]),
            _section('Cost of each part', [
              for (final c in ((est['categories'] as List?) ?? const []))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text('${c['label']}', style: const TextStyle(fontSize: 13.5))),
                      if (_i(c['spent']) > 0)
                        Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: Text('spent ${creditsLabel(_i(c['spent']))}', style: _muted),
                        ),
                      Text(_i(c['remaining_max']) > 0 ? 'up to ${creditsLabel(_i(c['remaining_max']))}' : '—',
                          style: const TextStyle(fontWeight: FontWeight.w600, fontFeatures: [FontFeature.tabularFigures()])),
                    ]),
                    for (final n in _list(c['notes'])) Text(n, style: _small),
                  ]),
                ),
            ]),
            _section('The most it can cost', [
              _row('Every step at its highest price', creditsLabel(_i(est['steps_max'] ?? q['steps_credits']))),
              _row('Safety margin for price changes', creditsLabel(_i(est['safety_credits'] ?? q['safety_credits']))),
              const Divider(height: 16),
              _row('Maximum (reserved when you start)', creditsLabel(total), bold: true),
              _row('Estimated credit value', '≈ \$${(total * value).toStringAsFixed(2)}'),
              Text('${terms['credit_value_label'] ?? ''}', style: _small),
              if (paid != null && _i(paid['credits']) > 0)
                Text('Your last credit pack: ${creditsLabel(_i(paid['credits']))} for '
                    '\$${((paid['price_usd'] as num?) ?? 0).toStringAsFixed(2)} (the price you actually paid).',
                    style: _small),
              const SizedBox(height: 6),
              Text('${est['uncertainty'] ?? ''}', style: _muted),
              const SizedBox(height: 6),
              _row('Your balance', creditsLabel(available)),
              if (short)
                Text('You need ${creditsLabel(total - available)} more to start.',
                    style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600)),
            ]),
            _section('Your budget is protected', [for (final t in _list(terms['budget'])) _bullet(t)]),
            _section('Options', [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: storyboard,
                title: const Text('Review the storyboard before video', style: TextStyle(fontSize: 13.5)),
                subtitle: Text(_list(terms['storyboard']).isNotEmpty ? _list(terms['storyboard']).first : '',
                    style: const TextStyle(fontSize: 11.5)),
                onChanged: busy ? null : (v) => v ? setState(() => storyboard = true) : _storyboardOff(),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: direct,
                title: const Text('Direct every scene automatically', style: TextStyle(fontSize: 13.5)),
                subtitle: const Text('The AI director films each scene as several shots. Recommended.',
                    style: TextStyle(fontSize: 11.5)),
                onChanged: busy ? null : (v) => _change(d: v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: sheets,
                title: const Text('Character reference sheets', style: TextStyle(fontSize: 13.5)),
                subtitle: const Text('Keeps every character the same person in every scene. Recommended.',
                    style: TextStyle(fontSize: 11.5)),
                onChanged: busy ? null : (v) => _change(s: v),
              ),
            ]),
            _section('If something fails', [for (final t in _list(terms['failures'])) _bullet(t)]),
            _section('Revisions included', [for (final t in _list(terms['revisions'])) _bullet(t)]),
            _section('Publishing and export', [for (final t in _list(terms['publishing'])) _bullet(t)]),
            _section('Credits, Coins and Premium', [for (final t in _list(terms['currencies'])) _bullet(t)]),
            if (blocked.isNotEmpty)
              _section('Fix these first', [for (final b in blocked.take(8)) _bullet(b, color: AppColors.danger)]),
            for (final a in _list(q['advice'])) _bullet('Better coverage: $a', color: AppColors.coin),
          ]),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            if (((q['single_shot_scenes'] as List?) ?? const []).isNotEmpty)
              TextButton(
                onPressed: () => Navigator.pop(context, {'plan_shots': _list(q['single_shot_scenes'])}),
                child: const Text('Plan shots first'),
              ),
            if (short && canStart)
              FilledButton(onPressed: () => Navigator.pop(context, {'credits': true}), child: const Text('Get credits'))
            else
              FilledButton(
                onPressed: canStart
                    ? () => Navigator.pop(context,
                        {'total': total, 'sheets': sheets, 'direct': direct, 'storyboard': storyboard})
                    : null,
                child: Text('Reserve up to ${creditsLabel(total)} & start'),
              ),
          ]),
        ),
      ),
    );
  }

  static const _muted = TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.4);
  static const _small = TextStyle(color: AppColors.textMuted, fontSize: 11, height: 1.35);

  Widget _section(String title, List<Widget> children) => Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(14),
        decoration: studioPanel(),
        child: Material(
          type: MaterialType.transparency,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
            const SizedBox(height: 8),
            ...children,
          ]),
        ),
      );

  Widget _row(String a, String b, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(child: Text(a, style: TextStyle(fontSize: 13, fontWeight: bold ? FontWeight.w800 : FontWeight.w400))),
          Text(b,
              style: TextStyle(
                  fontSize: bold ? 15 : 13,
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                  color: bold ? AppColors.coin : null,
                  fontFeatures: const [FontFeature.tabularFigures()])),
        ]),
      );

  Widget _bullet(String t, {Color? color}) => Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('•  ', style: TextStyle(color: color ?? AppColors.textMuted)),
          Expanded(child: Text(t, style: TextStyle(fontSize: 12.5, height: 1.4, color: color))),
        ]),
      );
}
