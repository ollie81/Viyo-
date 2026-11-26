import 'package:flutter/material.dart';

import '../../services/brand_campaign_service.dart';
import '../../theme/app_theme.dart';
import 'brand_campaigns_screen.dart' show StatusChip, applicationStatus;

String _err(Object e) => '$e'.replaceFirst(RegExp(r'^Exception:\s*'), '');

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
String _date(DateTime? d) {
  if (d == null) return '—';
  final l = d.toLocal();
  return '${_months[l.month - 1]} ${l.day}';
}

/// Brand deals for creators: open campaigns to apply to, and your own deals (make the post, submit it, get paid).
class BrandDealsScreen extends StatefulWidget {
  const BrandDealsScreen({super.key, this.api = const BrandCampaignApi()});
  final BrandCampaignApi api;

  @override
  State<BrandDealsScreen> createState() => _BrandDealsScreenState();
}

class _BrandDealsScreenState extends State<BrandDealsScreen> {
  OpenCampaigns? _open;
  List<BrandApplication>? _deals;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait([widget.api.open(), widget.api.deals()]);
      if (!mounted) return;
      setState(() {
        _open = r[0] as OpenCampaigns;
        _deals = r[1] as List<BrandApplication>;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = _err(e));
    }
  }

  Future<void> _do(Future<void> Function() action, String done) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_err(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _apply(BrandCampaign c) async {
    final ctrl = TextEditingController();
    final pitch = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Apply to ${c.brandName}'),
        content: TextField(
          controller: ctrl,
          maxLength: 500,
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(labelText: 'Why you? (optional)', hintText: 'Your idea for the post'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Apply')),
        ],
      ),
    );
    if (pitch == null) return;
    await _do(() => widget.api.apply(c.id, pitch), 'Applied. ${c.brandName} will decide.');
  }

  Future<void> _submit(BrandApplication a) async {
    List<MyPost> posts;
    try {
      posts = await widget.api.myPosts();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_err(e))));
      return;
    }
    if (!mounted) return;
    final chosen = await showModalBottomSheet<MyPost>(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (ctx) => SafeArea(
        child: posts.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Text('Publish your post on VIYO first (public), then come back to submit it.',
                    textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary)),
              )
            : ListView(shrinkWrap: true, children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text('Which post did you make for this deal?', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text('It will be labelled "Sponsored".', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                ),
                for (final p in posts)
                  ListTile(
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: p.thumbnailUrl != null
                          ? Image.network(p.thumbnailUrl!, width: 44, height: 58, fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(width: 44, height: 58, color: AppColors.background))
                          : Container(width: 44, height: 58, color: AppColors.background,
                              child: const Icon(Icons.movie_outlined, size: 18)),
                    ),
                    title: Text(p.caption.isEmpty ? 'Untitled post' : p.caption, maxLines: 2, overflow: TextOverflow.ellipsis),
                    onTap: () => Navigator.pop(ctx, p),
                  ),
              ]),
      ),
    );
    if (chosen == null) return;
    await _do(() => widget.api.submit(a.id, chosen.id), 'Submitted. The brand has been told.');
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          title: const Text('Brand deals'),
          bottom: TabBar(tabs: [
            const Tab(text: 'Open campaigns'),
            Tab(text: 'My deals${(_deals?.isNotEmpty ?? false) ? ' (${_deals!.length})' : ''}'),
          ]),
        ),
        body: _open == null
            ? Center(
                child: _error == null
                    ? const CircularProgressIndicator()
                    : Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary)),
                          const SizedBox(height: 10),
                          OutlinedButton(onPressed: _load, child: const Text('Try again')),
                        ]),
                      ))
            : TabBarView(children: [
                RefreshIndicator(onRefresh: _load, child: _openList(_open!)),
                RefreshIndicator(onRefresh: _load, child: _dealList(_deals ?? const [])),
              ]),
      ),
    );
  }

  Widget _openList(OpenCampaigns o) => ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 32), children: [
        if (!o.eligible)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: AppTheme.card(),
            child: Text(
              'Brand deals are for ${o.minLevel} creators and above. You\'re ${o.level}: your Creator Hub shows what '
              'you still need.',
              style: const TextStyle(fontSize: 12.5, height: 1.4),
            ),
          ),
        const Text('Brands pay through VIYO. You get 80% of the fee when the brand approves your post (or after 7 '
            'days if they don\'t decide), held like your other earnings.',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted, height: 1.4)),
        const SizedBox(height: 12),
        if (o.campaigns.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 30),
            child: Text('No open campaigns right now. Check back soon.',
                textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted)),
          ),
        for (final c in o.campaigns)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: AppTheme.card(),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(c.brandName, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                    Text(c.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  ]),
                ),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(usd(c.creatorGetsUsd),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.success)),
                  const Text('for you', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                ]),
              ]),
              const SizedBox(height: 8),
              Text(c.brief, maxLines: 5, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.4)),
              if (c.deliverable.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text('Deliver: ${c.deliverable}', style: const TextStyle(fontSize: 12)),
              ],
              const SizedBox(height: 6),
              Text('${c.slots} ${c.slots == 1 ? 'creator' : 'creators'} · post by ${_date(c.deadline)}',
                  style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
              const SizedBox(height: 10),
              if (c.myApplication != null)
                Builder(builder: (_) {
                  final s = applicationStatus(c.myApplication!.status);
                  return StatusChip(s.text, s.color);
                })
              else
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: o.eligible && !_busy ? () => _apply(c) : null,
                    child: const Text('Apply'),
                  ),
                ),
            ]),
          ),
      ]);

  Widget _dealList(List<BrandApplication> deals) => ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 32), children: [
        if (deals.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 30),
            child: Text('Campaigns you apply to show here.',
                textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted)),
          ),
        for (final a in deals)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: AppTheme.card(),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text('${a.campaign?.brandName ?? ''} · ${a.campaign?.title ?? ''}',
                      maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                Builder(builder: (_) {
                  final s = applicationStatus(a.status);
                  return StatusChip(a.autoApproved ? 'Approved · paid' : s.text, s.color);
                }),
              ]),
              const SizedBox(height: 4),
              Text(
                switch (a.status) {
                  'applied' => 'Waiting for the brand to decide.',
                  'accepted' => 'You\'re in! Publish your post on VIYO and submit it by ${_date(a.campaign?.deadline)}. '
                      'You get ${usd(a.campaign?.creatorGetsUsd ?? 0)}.',
                  'submitted' => 'Submitted. The brand approves it, or it\'s approved automatically on '
                      '${_date(a.autoApprovesAt)}.',
                  'approved' => 'Paid ${usd(a.campaign?.creatorGetsUsd ?? 0)} to your earnings (held like your other '
                      'earnings before you can withdraw it).',
                  'rejected' => 'Not approved${a.decisionNote.isNotEmpty ? ': ${a.decisionNote}' : '.'}',
                  'expired' => 'The deadline passed.',
                  _ => '',
                },
                style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.4),
              ),
              if (a.status == 'accepted') ...[
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: ElevatedButton(
                        onPressed: _busy ? null : () => _submit(a), child: const Text('Submit your post')),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                      onPressed: _busy ? null : () => _do(() => widget.api.withdraw(a.id), 'Withdrawn.'),
                      child: const Text('Withdraw')),
                ]),
              ] else if (a.status == 'applied')
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                      onPressed: _busy ? null : () => _do(() => widget.api.withdraw(a.id), 'Withdrawn.'),
                      child: const Text('Withdraw')),
                ),
            ]),
          ),
      ]);
}
