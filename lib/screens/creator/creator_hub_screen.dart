import 'dart:async';

import 'package:flutter/material.dart';
import '../../services/ad_revenue_service.dart';
import '../../services/creator_hub_service.dart';
import '../../services/series_service.dart';
import '../../theme/app_theme.dart';
import '../post/series_detail_screen.dart';
import '../post/upload_ai_drama_screen.dart';
import '../studio/studio_home_screen.dart';
import '../wallet_screen.dart';
import 'brand_campaigns_screen.dart';
import 'brand_deals_screen.dart';
import 'my_productions_screen.dart';

String _n(int v) => v >= 1000000 ? '${(v / 1000000).toStringAsFixed(1)}M' : v >= 1000 ? '${(v / 1000).toStringAsFixed(1)}K' : '$v';
String _usd(double v) => '\$${v.toStringAsFixed(2)}';

/// Creator Hub: create, publish, see how it does, see what you earned and how earning works, get paid.
/// Every number comes from the server's real records; the earning rules come from the same constants the
/// payment code uses, so nothing here promises more than VIYO pays.
class CreatorHubScreen extends StatefulWidget {
  const CreatorHubScreen({super.key, this.loadHub, this.loadAnalytics, this.loadAdRevenue});

  /// For tests; the real screen asks the server.
  final Future<CreatorHub> Function()? loadHub;
  final Future<CreatorAnalytics?> Function()? loadAnalytics;
  final Future<AdRevenueSummary> Function()? loadAdRevenue;

  /// While the screen is open it refreshes itself this often (quietly, no spinner).
  static const refreshEvery = Duration(seconds: 60);

  @override
  State<CreatorHubScreen> createState() => _CreatorHubScreenState();
}

class _CreatorHubScreenState extends State<CreatorHubScreen> {
  CreatorHub? _hub;
  CreatorAnalytics? _analytics;
  AdRevenueSummary? _ads;
  String? _error;
  bool _loading = true;
  DateTime? _updatedAt;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(CreatorHubScreen.refreshEvery, (_) => _refreshQuietly());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _fetch() async {
    final hub = await (widget.loadHub ?? CreatorHubService.load)();
    final analytics = await (widget.loadAnalytics ?? CreatorAnalytics.load)();
    final ads = hub.dashboard?.advertisingNote == null && hub.dashboard != null
        ? await (widget.loadAdRevenue ?? AdRevenueService.mine)()
        : null;
    if (!mounted) return;
    _hub = hub;
    _analytics = analytics;
    _ads = ads;
    _updatedAt = DateTime.now();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _fetch();
    } catch (e) {
      _error = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// The minute-by-minute refresh: keeps what's on screen if the server can't be reached this time.
  Future<void> _refreshQuietly() async {
    if (_loading || _hub == null || !mounted) return;
    try {
      await _fetch();
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _go(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    if (mounted) _load();
  }

  Future<void> _openSeries(String id) async {
    try {
      final s = await SeriesService.getSeries(id);
      if (s != null && mounted) await _go(SeriesDetailScreen(series: s));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: AppColors.background, title: const Text('Creator Hub')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary)),
                      const SizedBox(height: 10),
                      OutlinedButton(onPressed: _load, child: const Text('Try again')),
                    ]),
                  ),
                )
              : RefreshIndicator(onRefresh: _load, child: _content(_hub!)),
    );
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(top: 22, bottom: 8),
        child: Text(t, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
      );

  Widget _content(CreatorHub h) {
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 8, 16, 32 + MediaQuery.paddingOf(context).bottom),
      children: [
        // Create → publish
        Row(children: [
          Expanded(child: _action(Icons.movie_creation_outlined, 'Create in Studio', 'From an idea, no camera needed',
              () => _go(const StudioHomeScreen()))),
          const SizedBox(width: 10),
          Expanded(child: _action(Icons.upload_outlined, 'Upload', 'Episodes, short films, movies',
              () => _go(const UploadAiDramaScreen()))),
        ]),
        if (h.dashboard?.brandNote == null && h.dashboard != null) ...[
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _action(Icons.handshake_outlined, 'Brand deals', 'Get paid by brands for a post',
                () => _go(const BrandDealsScreen()))),
            const SizedBox(width: 10),
            Expanded(child: _action(Icons.campaign_outlined, 'Run a campaign', 'Pay creators to post about you',
                () => _go(const BrandCampaignsScreen()))),
          ]),
        ],
        if (h.dashboard?.level?.ready == true) ..._levelCard(h.dashboard!.level!),
        _label('Your audience'),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          decoration: AppTheme.card(),
          child: Row(children: [
            _stat('Views', h.views),
            _stat('Likes', h.likes),
            _stat('Comments', h.comments),
            _stat('Shares', h.shares),
            if (h.followers != null) _stat('Followers', h.followers!),
          ]),
        ),
        if (h.dashboard?.ready == true) ..._dashboardAudience(h.dashboard!),
        if (_analytics != null) ..._audienceDetail(_analytics!, showTotals: h.dashboard?.ready != true),
        _label('Earnings'),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: AppTheme.card(),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(_usd(h.availableUsd),
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, fontFeatures: [FontFeature.tabularFigures()])),
              const SizedBox(width: 8),
              const Padding(
                padding: EdgeInsets.only(bottom: 5),
                child: Text('available', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
              ),
            ]),
            const SizedBox(height: 4),
            Text(
              '${_n(h.availableCoins)} coins available · ${_n(h.last30Coins)} earned in the last 30 days · '
              '${_usd(h.lifetimeUsd)} all time${h.paidCoins > 0 ? ' · ${_usd(h.paidUsd)} paid out' : ''}',
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.35),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _go(const WalletScreen()),
                  child: Text(h.withdrawalPending
                      ? 'Withdrawal on its way'
                      : h.canWithdraw
                          ? (h.payoutDetailsSaved ? 'Withdraw' : 'Add payout details')
                          : 'Open Wallet'),
                ),
              ),
            ]),
          ]),
        ),
        if (h.dashboard?.ready == true) ..._dashboardEarnings(h.dashboard!)
        else if (h.dashboard != null)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('The detailed breakdown is being set up. Your totals above are up to date.',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
          ),
        if (_ads?.available == true) ..._adRevenueCard(_ads!),
        if (h.dashboard?.ready == true) ..._dashboardStudio(h.dashboard!),
        if (_updatedAt != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text('Updated ${_time(_updatedAt!)} · refreshes every minute while open',
                style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
          ),
        _label('Your productions'),
        if (h.productions.isEmpty)
          const Text('Nothing published yet. Create something in Studio or upload an episode, and it shows here.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12.5, height: 1.35))
        else
          for (final p in h.productions) _production(p),
        const SizedBox(height: 6),
        TextButton.icon(
          onPressed: () => _go(const MyProductionsScreen()),
          icon: const Icon(Icons.download_outlined, size: 18),
          label: const Text('Download your productions to post anywhere'),
        ),
        _label('How you earn on VIYO'),
        for (final e in h.earns)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: AppTheme.card(),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.check_circle_outline, size: 16, color: AppColors.success),
                const SizedBox(width: 6),
                Text(e.title, style: const TextStyle(fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 6),
              Text(e.detail, style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.4)),
            ]),
          ),
        const Padding(
          padding: EdgeInsets.only(top: 6, bottom: 6),
          child: Text("What doesn't earn money", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        ),
        for (final t in h.doesNotEarn)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('• $t', style: const TextStyle(fontSize: 12, color: AppColors.textMuted, height: 1.35)),
          ),
        const Padding(
          padding: EdgeInsets.only(top: 10, bottom: 6),
          child: Text('Getting paid', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        ),
        Text(h.payoutDetail, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.4)),
        if (h.note.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(h.note, style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted, height: 1.35)),
          ),
      ],
    );
  }

  List<Widget> _levelCard(CreatorLevel l) {
    String fmt(num v) => v is double && v != v.roundToDouble() ? v.toStringAsFixed(2) : _n(v.round());
    return [
      _label('Your creator level'),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: AppTheme.card(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(20)),
              child: Text(l.name,
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: AppColors.primary)),
            ),
            const SizedBox(width: 8),
            Text('Level ${l.rank} of ${l.of}', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
          ]),
          const SizedBox(height: 8),
          for (final p in l.perks)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(children: [
                const Icon(Icons.bolt, size: 16, color: AppColors.success),
                const SizedBox(width: 6),
                Expanded(child: Text(p, style: const TextStyle(fontSize: 12.5))),
              ]),
            ),
          if (l.nextName != null) ...[
            const SizedBox(height: 4),
            Text('To reach ${l.nextName}${l.nextPerk != null ? ' (${l.nextPerk!.toLowerCase()})' : ''}:',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
            const SizedBox(height: 8),
            for (final r in l.nextRequirements)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(r.met ? Icons.check_circle : Icons.radio_button_unchecked,
                        size: 15, color: r.met ? AppColors.success : AppColors.textMuted),
                    const SizedBox(width: 6),
                    Expanded(child: Text(r.label, style: const TextStyle(fontSize: 12))),
                    if (r.key != 'clean')
                      Text('${r.key == 'earned_usd' ? '\$' : ''}${fmt(r.have)} / ${r.key == 'earned_usd' ? '\$' : ''}${fmt(r.need)}',
                          style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted,
                              fontFeatures: [FontFeature.tabularFigures()])),
                  ]),
                  if (r.key != 'clean' && !r.met)
                    Padding(
                      padding: const EdgeInsets.only(left: 21, top: 4),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(value: r.progress, minHeight: 4),
                      ),
                    ),
                ]),
              ),
          ] else if (l.rank >= l.of)
            const Text("You're at the top level.", style: TextStyle(fontSize: 12.5)),
          if (l.shareNote.isNotEmpty)
            Text(l.shareNote, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
        ]),
      ),
    ];
  }

  List<Widget> _dashboardAudience(CreatorDashboard d) => [
        _label('Last ${d.days} days'),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          decoration: AppTheme.card(),
          child: Row(children: [
            _stat('Plays', d.plays),
            _stat('People', d.uniqueViewers),
            _stat('Watch min', d.watchMinutes),
            _statText('Finished', d.completionRate == null ? '—' : '${(d.completionRate! * 100).round()}%'),
          ]),
        ),
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text("Plays by other people; your own plays don't count. Finished = episodes watched to the end.",
              style: TextStyle(fontSize: 11, color: AppColors.textMuted, height: 1.35)),
        ),
      ];

  List<Widget> _dashboardEarnings(CreatorDashboard d) {
    const names = {
      'content': 'Paid content',
      'donations': 'Donations',
      'brand_deals': 'Brand deals',
      'ads': 'Ad revenue',
      'adjustments': 'Refunds and corrections',
    };
    return [
      _label('Earnings by type'),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: AppTheme.card(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final e in names.entries)
            if ((e.key != 'adjustments' &&
                    (e.key != 'brand_deals' || d.brandNote == null) &&
                    (e.key != 'ads' || d.advertisingNote == null)) ||
                (d.byType[e.key]?.coins ?? 0) != 0)
              _earningRow(e.value, d.byType[e.key] ?? const EarningType()),
          if (d.advertisingNote != null) _notYetRow('Ad revenue', d.advertisingNote),
          if (d.brandNote != null) _notYetRow('Brand campaigns', d.brandNote),
          const Divider(height: 20),
          Row(children: [
            Expanded(child: _money('On hold', d.heldUsd, '${_n(d.heldCoins)} coins')),
            Expanded(child: _money('Available', d.availableUsd, '${_n(d.availableCoins)} coins')),
          ]),
          const SizedBox(height: 8),
          Text('New earnings are held for ${d.holdDays} days in case of refunds, then become available to withdraw.',
              style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted, height: 1.35)),
        ]),
      ),
      if (d.withdrawals.isNotEmpty) ...[
        _label('Withdrawals'),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: AppTheme.card(),
          child: Column(children: [
            for (final w in d.withdrawals)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(children: [
                  Expanded(
                    child: Text(w.createdAt == null ? '—' : _date(w.createdAt!),
                        style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                  ),
                  Text(_usd(w.usd),
                      style: const TextStyle(fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()])),
                  const SizedBox(width: 10),
                  _statusChip(w.status),
                ]),
              ),
          ]),
        ),
      ],
    ];
  }

  List<Widget> _adRevenueCard(AdRevenueSummary a) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    String label(String ym) {
      final p = ym.split('-');
      final m = p.length == 2 ? int.tryParse(p[1]) : null;
      return m == null || m < 1 || m > 12 ? ym : '${months[m - 1]} ${p[0]}';
    }

    final t = a.thisMonth;
    return [
      _label('Ad revenue'),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: AppTheme.card(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('This month so far: ${_n(t.feedAds + t.unlockAds)} ads on your content',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(height: 2),
          Text('${_n(t.feedAds)} in your videos and feed · ${_n(t.unlockAds)} to unlock your episodes',
              style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
          const SizedBox(height: 6),
          Text('You get ${(a.creatorShare * 100).round()}% of what these ads really earn. The amount is added after '
              'the month ends, from VIYO\'s ad report.',
              style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary, height: 1.35)),
          if (a.months.isNotEmpty) ...[
            const Divider(height: 20),
            for (final m in a.months.take(6))
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(children: [
                  Expanded(child: Text(label(m.month), style: const TextStyle(fontSize: 12.5))),
                  Text('${_n(m.feedAds + m.unlockAds)} ads',
                      style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
                  const SizedBox(width: 12),
                  Text(_usd(m.usd),
                      style: const TextStyle(fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()])),
                ]),
              ),
          ],
        ]),
      ),
    ];
  }

  List<Widget> _dashboardStudio(CreatorDashboard d) => [
        _label('Studio'),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          decoration: AppTheme.card(),
          child: Row(children: [
            _stat('Projects', d.projects),
            _stat('In progress', d.activeJobs),
            _stat('Finished', d.completedJobs),
            _stat('Failed', d.failedJobs),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('${_n(d.creditsUsedPeriod)} credits used in the last ${d.days} days · ${_n(d.creditsUsed)} all time',
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        ),
      ];

  Widget _earningRow(String name, EarningType t) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              const SizedBox(height: 2),
              Text(
                [
                  '${_n(t.coins)} coins',
                  if (t.heldCoins > 0) '${_n(t.heldCoins)} on hold',
                  if (t.paidCoins > 0) '${_n(t.paidCoins)} paid out',
                ].join(' · '),
                style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
              ),
            ]),
          ),
          Text(t.usd < 0 ? '-${_usd(-t.usd)}' : _usd(t.usd),
              style: const TextStyle(fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()])),
        ]),
      );

  Widget _notYetRow(String name, String? note) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Expanded(child: Text(name, style: const TextStyle(fontSize: 13, color: AppColors.textMuted))),
          Text(note == null ? '' : 'Not available yet', style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
        ]),
      );

  Widget _money(String label, double usd, String sub) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
        const SizedBox(height: 2),
        Text(_usd(usd),
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()])),
        Text(sub, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
      ]);

  Widget _statusChip(String status) {
    final (text, color) = switch (status) {
      'paid' => ('Paid', AppColors.success),
      'pending' => ('Requested', AppColors.coin),
      'approved' => ('Approved', AppColors.coin),
      'rejected' => ('Rejected', AppColors.textMuted),
      _ => (status.isEmpty ? '—' : status, AppColors.textMuted),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
      child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
    );
  }

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  String _date(DateTime d) {
    final l = d.toLocal();
    return '${_months[l.month - 1]} ${l.day}, ${l.year}';
  }

  String _time(DateTime d) {
    final l = d.toLocal();
    return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }

  Widget _statText(String label, String v) => Expanded(
        child: Column(children: [
          Text(v, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()])),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted)),
        ]),
      );

  List<Widget> _audienceDetail(CreatorAnalytics a, {bool showTotals = true}) {
    final completion = a.uniqueViewers > 0 ? a.completers / a.uniqueViewers : null;
    return [
      if (showTotals) ...[
      _label('Last 30 days'),
      Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: AppTheme.card(),
        child: Row(children: [
          _stat('People', a.uniqueViewers),
          _stat('Finished', a.completers),
          _stat('Watch min', a.watchMinutes.round()),
          _stat('New followers', a.newFollowers),
        ]),
      ),
      if (completion != null)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('${(completion * 100).round()}% of the people who started your work finished something.',
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        ),
      ] else if (a.newFollowers > 0)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('${_n(a.newFollowers)} new followers in the last 30 days',
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        ),
      if (a.advice.isNotEmpty) ...[
        _label('What your numbers say'),
        for (final x in a.advice)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: AppTheme.card(),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(x.text, style: const TextStyle(fontSize: 12.5, height: 1.4)),
              const SizedBox(height: 4),
              Text('Based on ${x.basedOn}', style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
            ]),
          ),
      ],
      if (a.note.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(a.note, style: const TextStyle(fontSize: 11, color: AppColors.textMuted, height: 1.35)),
        ),
    ];
  }

  Widget _action(IconData icon, String title, String sub, VoidCallback onTap) => Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icon, color: AppColors.primary),
              const SizedBox(height: 8),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
              const SizedBox(height: 2),
              Text(sub, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
            ]),
          ),
        ),
      );

  Widget _stat(String label, int v) => Expanded(
        child: Column(children: [
          Text(_n(v), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()])),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted)),
        ]),
      );

  Widget _production(HubProduction p) {
    final type = switch (p.contentType) {
      'movie' => 'Movie',
      'short_film' => 'Short film',
      'ai_film' => 'AI film',
      'series' => 'Series',
      'video' => 'Video',
      _ => 'Drama',
    };
    final paid = p.kind == 'series'
        ? (p.earns ? '${p.coinPrice} coins per episode' : 'Free: set a price on the series page to earn')
        : 'Video post';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: p.coverUrl != null
            ? Image.network(p.coverUrl!, width: 46, height: 62, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(width: 46, height: 62, color: AppColors.surface))
            : Container(width: 46, height: 62, color: AppColors.surface, child: const Icon(Icons.movie_outlined, size: 18)),
      ),
      title: Text(p.title.isEmpty ? type : p.title, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
      subtitle: Text(
        '$type${p.kind == 'series' ? ' · ${p.publicEpisodes}/${p.episodes} public' : ''} · $paid\n'
        '${_n(p.views)} views · ${_n(p.likes)} likes · ${_n(p.comments)} comments · ${_n(p.shares)} shares',
        style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted, height: 1.35),
      ),
      isThreeLine: true,
      trailing: p.earnedCoins > 0
          ? Text('${_n(p.earnedCoins)}\ncoins', textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: AppColors.coin))
          : null,
      onTap: p.kind == 'series' ? () => _openSeries(p.id) : null,
    );
  }
}
