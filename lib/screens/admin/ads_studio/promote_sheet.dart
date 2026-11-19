import 'package:flutter/material.dart';
import '../../../services/promotion_service.dart';
import '../../../theme/app_theme.dart';

String _msg(Object e) => e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');

/// Choose a budget and length, see the full price and terms, then pay (coins) to promote a published ad.
Future<bool> showPromoteSheet(BuildContext context, String postId) async {
  final started = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    builder: (_) => _PromoteSheet(postId: postId),
  );
  return started == true;
}

class _PromoteSheet extends StatefulWidget {
  final String postId;
  const _PromoteSheet({required this.postId});

  @override
  State<_PromoteSheet> createState() => _PromoteSheetState();
}

class _PromoteSheetState extends State<_PromoteSheet> {
  int _budget = 500;
  int _days = 3;
  final Set<String> _placements = {'for_you', 'ads'};
  PromotionQuote? _quote;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final q = await PromotionService.quote(_budget, _days);
      if (mounted) setState(() {
        _quote = q;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = _msg(e));
    }
  }

  Future<void> _start() async {
    setState(() => _busy = true);
    try {
      await PromotionService.start(widget.postId, _budget, _days, _placements.toList());
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = _msg(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _quote;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 12 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Promote this ad', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 12),
          const Text('Budget (coins)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Wrap(spacing: 6, children: [
            for (final b in const [100, 250, 500, 1000, 2500])
              ChoiceChip(
                label: Text('$b'),
                selected: _budget == b,
                onSelected: (_) {
                  setState(() => _budget = b);
                  _refresh();
                },
              ),
          ]),
          const SizedBox(height: 12),
          const Text('Length', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Wrap(spacing: 6, children: [
            for (final d in const [1, 3, 7, 14])
              ChoiceChip(
                label: Text(d == 1 ? '1 day' : '$d days'),
                selected: _days == d,
                onSelected: (_) {
                  setState(() => _days = d);
                  _refresh();
                },
              ),
          ]),
          const SizedBox(height: 12),
          const Text('Where', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          Wrap(spacing: 6, children: [
            for (final e in const {'for_you': 'Discover: For You', 'ads': 'Discover: Ads'}.entries)
              FilterChip(
                label: Text(e.value),
                selected: _placements.contains(e.key),
                onSelected: (on) => setState(() => on ? _placements.add(e.key) : _placements.remove(e.key)),
              ),
          ]),
          const SizedBox(height: 14),
          if (q != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: AppTheme.card(),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('$_budget coins · up to ${q.maxImpressions} people reached',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                const SizedBox(height: 2),
                Text('${q.coinsPer1000} coins per 1,000 · about ${q.perDayCoins.toStringAsFixed(0)} coins a day',
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                const SizedBox(height: 8),
                for (final t in q.terms)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text('• $t', style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted, height: 1.35)),
                  ),
              ]),
            ),
            const SizedBox(height: 12),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 12.5)),
            ),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _busy || q == null || !q.enabled || _placements.isEmpty ? null : _start,
              child: Text(q != null && !q.enabled
                  ? 'Paid promotion is not open yet'
                  : _busy
                      ? 'Starting...'
                      : 'Pay $_budget coins and promote'),
            ),
          ),
        ]),
      ),
    );
  }
}
