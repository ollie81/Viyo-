import 'package:flutter/material.dart';
import '../../../services/ad_insights_service.dart';
import '../../../services/ads_studio_service.dart';
import '../../../services/promotion_service.dart';
import '../../../theme/app_theme.dart';
import 'ads_result_screen.dart';
import 'ads_studio_wizard_screen.dart';

String _msg(Object e) => e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
String _n(int v) => v >= 1000000 ? '${(v / 1000000).toStringAsFixed(1)}M' : v >= 1000 ? '${(v / 1000).toStringAsFixed(1)}K' : '$v';
String _pct(double? r) => r == null ? '—' : '${(r * 100).toStringAsFixed(1)}%';

const kExperimentTones = {
  'funny': 'Funny',
  'emotional': 'Emotional',
  'cinematic': 'Cinematic',
  'storytelling': 'Storytelling',
  'demo': 'Product demonstration',
  'character': 'Character-led',
};

/// Asks which versions to make (2-6 tones), creates them as drafts, and opens the experiment.
Future<void> startExperiment(BuildContext context, String brandId, String brandName, {bool hasCharacter = false}) async {
  final picked = <String>{'funny', 'emotional'};
  String aspect = '9:16';
  final go = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Try versions of an ad for $brandName', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 4),
            const Text(
              'Each version is a separate draft in a different tone. Nothing is charged now: you see the price of each '
              'before generating it. Publish them and VIYO compares real engagement once there is enough.',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted, height: 1.35),
            ),
            const SizedBox(height: 14),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final e in kExperimentTones.entries)
                FilterChip(
                  label: Text(e.value),
                  selected: picked.contains(e.key),
                  onSelected: (on) => set(() => on ? picked.add(e.key) : picked.remove(e.key)),
                ),
            ]),
            const SizedBox(height: 12),
            Wrap(spacing: 6, children: [
              for (final a in const ['9:16', '16:9', '1:1'])
                ChoiceChip(label: Text(a), selected: aspect == a, onSelected: (_) => set(() => aspect = a)),
            ]),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: picked.length >= 2 && picked.length <= 6 ? () => Navigator.pop(ctx, true) : null,
                child: Text(picked.length < 2 ? 'Pick at least 2' : 'Make ${picked.length} drafts'),
              ),
            ),
          ]),
        ),
      ),
    ),
  );
  if (go != true || !context.mounted) return;
  try {
    final order = kExperimentTones.keys.toList();
    final tones = picked.toList()..sort((a, b) => order.indexOf(a).compareTo(order.indexOf(b)));
    final e = await AdInsightsService.createExperiment(brandId, tones, aspectRatio: aspect, useCharacter: hasCharacter);
    if (!context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ExperimentScreen(experimentId: e.id)));
  } catch (err) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_msg(err))));
  }
}

/// Insights for the creator's own published ads: organic and paid kept apart, real counts only.
class AdsInsightsScreen extends StatefulWidget {
  const AdsInsightsScreen({super.key});

  @override
  State<AdsInsightsScreen> createState() => _AdsInsightsScreenState();
}

class _AdsInsightsScreenState extends State<AdsInsightsScreen> {
  int _days = 30;
  bool _loading = true;
  String? _error;
  AdInsights? _data;
  List<AdExperiment> _experiments = [];
  List<AdPromotion> _promotions = [];
  String _promoNote = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _stopPromotion(AdPromotion p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Stop this promotion?'),
        content: Text('It stops now and the ${p.budgetCoins - p.coinsSpent} unused coins go back to your wallet.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep it')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Stop')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await PromotionService.stop(p.id);
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_msg(e))));
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await Future.wait([AdInsightsService.insights(days: _days), AdInsightsService.experiments()]);
      _data = r[0] as AdInsights;
      _experiments = r[1] as List<AdExperiment>;
      try {
        final m = await PromotionService.mine();
        _promotions = m.promotions;
        _promoNote = m.note;
      } catch (_) {
        _promotions = [];
      }
    } catch (e) {
      _error = _msg(e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: AppColors.background, title: const Text('Ad insights')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(_error!, style: const TextStyle(color: AppColors.danger)),
                    const SizedBox(height: 10),
                    OutlinedButton(onPressed: _load, child: const Text('Try again')),
                  ]),
                )
              : RefreshIndicator(onRefresh: _load, child: _content(_data!)),
    );
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 8),
        child: Text(t, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
      );

  Widget _content(AdInsights d) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
      children: [
        Wrap(spacing: 6, children: [
          for (final n in const [7, 30, 90])
            ChoiceChip(
              label: Text('$n days'),
              selected: _days == n,
              onSelected: (_) {
                setState(() => _days = n);
                _load();
              },
            ),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _totalsCard('Organic', d.organicAds, d.organic, AppColors.primary)),
          const SizedBox(width: 10),
          Expanded(child: _totalsCard('Paid (boosted)', d.paidAds, d.paid, AppColors.secondary)),
        ]),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: AppTheme.card(),
          child: Row(children: [
            const Icon(Icons.group_outlined, size: 18, color: AppColors.textSecondary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                d.followers == null
                    ? 'Followers unavailable right now'
                    : '${_n(d.followers!)} followers'
                        '${d.followersGained == null ? '' : ' · +${d.followersGained} in ${d.days} days'}',
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ]),
        ),
        _label('Likes and comments per day'),
        _TrendBars(trend: d.trend),
        if (d.trend.any((t) => t.views != null)) ...[
          _label('Views per day'),
          _TrendBars(trend: d.trend, views: true),
        ],
        for (final n in d.notes)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(n, style: const TextStyle(fontSize: 11, color: AppColors.textMuted, height: 1.35)),
          ),
        _label('Your ads'),
        if (d.posts.isEmpty)
          const Text('No published ads yet. Publish an ad to VIYO to see how it does.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12.5))
        else
          for (final p in d.posts) _postRow(p),
        if (_promotions.isNotEmpty) ...[
          _label('My promotions'),
          for (final p in _promotions)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: AppTheme.card(),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Text(p.caption.isEmpty ? 'Ad' : p.caption, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                  ),
                  Text(
                    p.active ? 'Running' : _endedLabel(p.endedReason),
                    style: TextStyle(fontSize: 11.5, color: p.active ? AppColors.success : AppColors.textMuted,
                        fontWeight: FontWeight.w700),
                  ),
                ]),
                const SizedBox(height: 6),
                Text('${_n(p.impressions)} people reached · ${_n(p.clicks)} visits',
                    style: const TextStyle(fontSize: 12.5)),
                Text(
                  '${p.coinsSpent} of ${p.budgetCoins} coins used'
                  '${p.coinsRefunded != null ? ' · ${p.coinsRefunded} returned' : ''}',
                  style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                ),
                if (p.active)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(onPressed: () => _stopPromotion(p), child: const Text('Stop and get unused coins back')),
                  ),
              ]),
            ),
          if (_promoNote.isNotEmpty)
            Text(_promoNote, style: const TextStyle(fontSize: 11, color: AppColors.textMuted, height: 1.35)),
        ],
        _label('Experiments'),
        if (_experiments.isEmpty)
          const Text('No experiments yet. Start one from a brand: "Try versions".',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12.5))
        else
          for (final e in _experiments)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.science_outlined),
              title: Text(e.name, style: const TextStyle(fontSize: 13.5)),
              subtitle: Text(
                e.verdict == 'leader' ? '${e.leader} is ahead so far' : '${e.variants.length} versions · ${_verdictShort(e.verdict)}',
                style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ExperimentScreen(experimentId: e.id)));
                if (mounted) _load();
              },
            ),
      ],
    );
  }

  Widget _totalsCard(String title, int ads, AdStats s, Color accent) => Container(
        padding: const EdgeInsets.all(12),
        decoration: AppTheme.card(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: accent, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Expanded(child: Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
          ]),
          const SizedBox(height: 8),
          Text(_n(s.views), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, fontFeatures: [FontFeature.tabularFigures()])),
          const Text('views', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
          const SizedBox(height: 6),
          Text('${_n(s.likes)} likes · ${_n(s.comments)} comments · ${_n(s.shares)} shares',
              style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
          Text('$ads ads · engagement ${_pct(s.engagementRate)}', style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
        ]),
      );

  Widget _postRow(AdInsightPost p) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: p.thumbnailUrl != null
              ? Image.network(p.thumbnailUrl!, width: 44, height: 56, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(width: 44, height: 56, color: AppColors.surface))
              : Container(width: 44, height: 56, color: AppColors.surface),
        ),
        title: Text(p.caption.isEmpty ? 'Ad' : p.caption, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13.5)),
        subtitle: Text(
          '${_n(p.stats.views)} views · ${_n(p.stats.likes)} likes · ${_n(p.stats.comments)} comments · '
          '${_n(p.stats.shares)} shares${p.paid ? ' · paid' : ''}${p.public ? '' : ' · private'}',
          style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
        ),
        trailing: Text(_pct(p.stats.engagementRate), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        onTap: p.campaignId == null
            ? null
            : () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => AdsResultScreen(adminKey: AdsStudioService.creator, campaignId: p.campaignId!),
                )),
      );
}

String _endedLabel(String? reason) => switch (reason) {
      'budget_used' => 'Budget used',
      'stopped' => 'Stopped',
      'ad_not_public' => 'Ended: ad not public',
      _ => 'Finished',
    };

String _verdictShort(String v) => switch (v) {
      'leader' => 'a version is ahead',
      'no_clear_difference' => 'no clear difference yet',
      _ => 'not enough data yet',
    };

/// Bars per day (likes + comments, or views from real snapshots; an unknown day is drawn empty, never guessed).
class _TrendBars extends StatelessWidget {
  final List<AdTrendDay> trend;
  final bool views;
  const _TrendBars({required this.trend, this.views = false});

  @override
  Widget build(BuildContext context) {
    final values = [for (final t in trend) views ? t.views : t.likes + t.comments];
    final max = values.whereType<int>().fold<int>(0, (a, b) => b > a ? b : a);
    return Container(
      height: 120,
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
      decoration: AppTheme.card(),
      child: Column(children: [
        Expanded(
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (final v in values)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 0.75),
                  child: v == null
                      ? Container(height: 2, color: AppColors.surfaceBorder)
                      : FractionallySizedBox(
                          heightFactor: max == 0 ? 0.02 : (v / max).clamp(0.02, 1.0),
                          child: Container(
                            decoration: BoxDecoration(
                              color: views ? AppColors.secondary : AppColors.primary,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 4),
        Row(children: [
          Text(trend.isEmpty ? '' : trend.first.day.substring(5), style: const TextStyle(fontSize: 9.5, color: AppColors.textMuted)),
          const Spacer(),
          Text('max ${_n(max)}', style: const TextStyle(fontSize: 9.5, color: AppColors.textMuted)),
          const Spacer(),
          Text(trend.isEmpty ? '' : trend.last.day.substring(5), style: const TextStyle(fontSize: 9.5, color: AppColors.textMuted)),
        ]),
      ]),
    );
  }
}

/// One experiment: its versions (draft, generated, published) and the comparison of real engagement.
class ExperimentScreen extends StatefulWidget {
  final String experimentId;
  const ExperimentScreen({super.key, required this.experimentId});

  @override
  State<ExperimentScreen> createState() => _ExperimentScreenState();
}

class _ExperimentScreenState extends State<ExperimentScreen> {
  AdExperiment? _e;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final e = await AdInsightsService.experiment(widget.experimentId);
      if (mounted) setState(() => _e = e);
    } catch (err) {
      if (mounted) setState(() => _error = _msg(err));
    }
  }

  Future<void> _open(AdVariant v) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => v.status == 'draft'
          ? AdsStudioWizardScreen(adminKey: AdsStudioService.creator, preselectedCampaignId: v.campaignId)
          : AdsResultScreen(adminKey: AdsStudioService.creator, campaignId: v.campaignId),
    ));
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final e = _e;
    return Scaffold(
      appBar: AppBar(backgroundColor: AppColors.background, title: Text(e?.name ?? 'Experiment')),
      body: _error != null
          ? Center(child: Text(_error!, style: const TextStyle(color: AppColors.danger)))
          : e == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 40), children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: (e.verdict == 'leader' ? AppColors.success : AppColors.surfaceBorder).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(e.message, style: const TextStyle(fontSize: 13, height: 1.35)),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Compared on public versions only, by likes, comments and shares per view. Versions published '
                      'at different times reach different people, so treat this as a guide, not a guarantee.',
                      style: TextStyle(fontSize: 11, color: AppColors.textMuted, height: 1.35),
                    ),
                    const SizedBox(height: 12),
                    for (final v in e.variants)
                      Card(
                        color: AppColors.surface,
                        child: ListTile(
                          leading: Icon(
                            v.label == e.leader ? Icons.emoji_events_outlined : Icons.movie_outlined,
                            color: v.label == e.leader ? AppColors.coin : AppColors.textSecondary,
                          ),
                          title: Text(v.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text(
                            !v.published
                                ? (v.status == 'draft' ? 'Draft: open to generate (price shown first)' : '${v.status.replaceAll('_', ' ')} · not published')
                                : '${v.public ? 'Public' : 'Private'} · ${_n(v.stats!.views)} views · '
                                    '${_n(v.stats!.likes + v.stats!.comments + v.stats!.shares)} engagements · '
                                    '${_pct(v.stats!.engagementRate)}',
                            style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _open(v),
                        ),
                      ),
                  ]),
                ),
    );
  }
}
