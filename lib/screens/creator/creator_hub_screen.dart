import 'package:flutter/material.dart';
import '../../services/creator_hub_service.dart';
import '../../services/series_service.dart';
import '../../theme/app_theme.dart';
import '../post/series_detail_screen.dart';
import '../post/upload_ai_drama_screen.dart';
import '../studio/studio_home_screen.dart';
import '../wallet_screen.dart';
import 'my_productions_screen.dart';

String _n(int v) => v >= 1000000 ? '${(v / 1000000).toStringAsFixed(1)}M' : v >= 1000 ? '${(v / 1000).toStringAsFixed(1)}K' : '$v';
String _usd(double v) => '\$${v.toStringAsFixed(2)}';

/// Creator Hub: create, publish, see how it does, see what you earned and how earning works, get paid.
/// Every number comes from the server's real records; the earning rules come from the same constants the
/// payment code uses, so nothing here promises more than VIYO pays.
class CreatorHubScreen extends StatefulWidget {
  const CreatorHubScreen({super.key});

  @override
  State<CreatorHubScreen> createState() => _CreatorHubScreenState();
}

class _CreatorHubScreenState extends State<CreatorHubScreen> {
  CreatorHub? _hub;
  CreatorAnalytics? _analytics;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _hub = await CreatorHubService.load();
      _analytics = await CreatorAnalytics.load();
    } catch (e) {
      _error = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
        if (_analytics != null) ..._audienceDetail(_analytics!),
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

  List<Widget> _audienceDetail(CreatorAnalytics a) {
    final completion = a.uniqueViewers > 0 ? a.completers / a.uniqueViewers : null;
    return [
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
