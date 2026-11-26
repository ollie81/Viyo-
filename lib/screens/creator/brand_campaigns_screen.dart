import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/brand_campaign_service.dart';
import '../../services/pending_purchase.dart';
import '../../services/post_service.dart';
import '../post/post_detail_screen.dart';
import '../../theme/app_theme.dart';

String _err(Object e) => '$e'.replaceFirst(RegExp(r'^Exception:\s*'), '');

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
String _date(DateTime? d) {
  if (d == null) return '—';
  final l = d.toLocal();
  return '${_months[l.month - 1]} ${l.day}';
}

({String text, Color color}) campaignStatus(String s) => switch (s) {
      'awaiting_payment' => (text: 'Waiting for payment', color: AppColors.coin),
      'open' => (text: 'Open', color: AppColors.success),
      'closed' => (text: 'Closed', color: AppColors.textMuted),
      'cancelled' => (text: 'Cancelled', color: AppColors.textMuted),
      _ => (text: s, color: AppColors.textMuted),
    };

({String text, Color color}) applicationStatus(String s) => switch (s) {
      'applied' => (text: 'Applied', color: AppColors.primary),
      'accepted' => (text: 'Picked', color: AppColors.coin),
      'submitted' => (text: 'Post submitted', color: AppColors.secondary),
      'approved' => (text: 'Approved · paid', color: AppColors.success),
      'rejected' => (text: 'Not approved', color: AppColors.danger),
      'declined' => (text: 'Not picked', color: AppColors.textMuted),
      'withdrawn' => (text: 'Withdrawn', color: AppColors.textMuted),
      'expired' => (text: 'Expired', color: AppColors.textMuted),
      _ => (text: s, color: AppColors.textMuted),
    };

class StatusChip extends StatelessWidget {
  final String text;
  final Color color;
  const StatusChip(this.text, this.color, {super.key});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
        child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
      );
}

/// A business's brand campaigns: create one, pay for it, pick creators and approve their posts.
class BrandCampaignsScreen extends StatefulWidget {
  const BrandCampaignsScreen({super.key, this.api = const BrandCampaignApi()});
  final BrandCampaignApi api;

  @override
  State<BrandCampaignsScreen> createState() => _BrandCampaignsScreenState();
}

class _BrandCampaignsScreenState extends State<BrandCampaignsScreen> {
  List<BrandCampaign>? _campaigns;
  double _credit = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await widget.api.mine();
      if (!mounted) return;
      setState(() {
        _campaigns = r.campaigns;
        _credit = r.creditUsd;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = _err(e));
    }
  }

  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final list = _campaigns;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(backgroundColor: AppColors.background, title: const Text('Brand campaigns')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(NewCampaignScreen(api: widget.api)),
        icon: const Icon(Icons.add),
        label: const Text('New campaign'),
      ),
      body: _error != null && list == null
          ? Center(
              child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary)),
                const SizedBox(height: 10),
                OutlinedButton(onPressed: _load, child: const Text('Try again')),
              ]),
            ))
          : list == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
                    const Text(
                      'Pay creators on VIYO to make a post about your brand. You pay the budget upfront; creators get '
                      '80% of the fee when you approve their post. Money that isn\'t used comes back as campaign credit.',
                      style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.4),
                    ),
                    if (_credit > 0) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: AppTheme.card(),
                        child: Row(children: [
                          const Icon(Icons.account_balance_wallet_outlined, color: AppColors.success, size: 20),
                          const SizedBox(width: 8),
                          Expanded(child: Text('${usd(_credit)} campaign credit — used first on your next campaign',
                              style: const TextStyle(fontSize: 12.5))),
                        ]),
                      ),
                    ],
                    const SizedBox(height: 14),
                    if (list.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 30),
                        child: Text('No campaigns yet.', textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.textMuted)),
                      ),
                    for (final c in list) _tile(c),
                  ]),
                ),
    );
  }

  Widget _tile(BrandCampaign c) {
    final s = campaignStatus(c.status);
    final toReview = c.count('submitted');
    final applicants = c.count('applied');
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _open(CampaignDetailScreen(campaignId: c.id, api: widget.api)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
                ),
                StatusChip(s.text, s.color),
              ]),
              const SizedBox(height: 4),
              Text('${c.brandName} · ${usd(c.feeUsd)} per creator · ${c.slots} '
                  '${c.slots == 1 ? 'creator' : 'creators'} · until ${_date(c.deadline)}',
                  style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
              if (toReview > 0 || applicants > 0) ...[
                const SizedBox(height: 8),
                Text(
                  [
                    if (toReview > 0) '$toReview ${toReview == 1 ? 'post' : 'posts'} to review',
                    if (applicants > 0) '$applicants new ${applicants == 1 ? 'applicant' : 'applicants'}',
                  ].join(' · '),
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.primary),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

/// The brief, the fee and the number of creators; then pay the budget by card through NardoPay.
class NewCampaignScreen extends StatefulWidget {
  const NewCampaignScreen({super.key, this.api = const BrandCampaignApi()});
  final BrandCampaignApi api;

  @override
  State<NewCampaignScreen> createState() => _NewCampaignScreenState();
}

class _NewCampaignScreenState extends State<NewCampaignScreen> {
  final _brand = TextEditingController();
  final _title = TextEditingController();
  final _brief = TextEditingController();
  final _deliverable = TextEditingController(text: 'One video post on VIYO');
  final _link = TextEditingController();
  final _fee = TextEditingController(text: '50');
  int _slots = 3;
  int _days = 14;
  CampaignOptions _opts = const CampaignOptions(available: false);
  double _credit = 0;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    for (final c in [_brand, _title, _brief, _fee]) {
      c.addListener(() => setState(() {}));
    }
    widget.api.options().then((o) {
      if (mounted) setState(() => _opts = o);
    });
    widget.api.credit().then((c) {
      if (mounted) setState(() => _credit = c);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    for (final c in [_brand, _title, _brief, _deliverable, _link, _fee]) {
      c.dispose();
    }
    super.dispose();
  }

  int? get _feeCents {
    final v = double.tryParse(_fee.text.trim().replaceAll(',', ''));
    if (v == null) return null;
    final cents = (v * 100).round();
    return cents < (_opts.feeMinUsd * 100).round() || cents > (_opts.feeMaxUsd * 100).round() ? null : cents;
  }

  bool get _valid =>
      _feeCents != null && _brand.text.trim().isNotEmpty && _title.text.trim().isNotEmpty &&
      _brief.text.trim().length >= 10;

  Future<void> _submit() async {
    final cents = _feeCents;
    if (!_valid || cents == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final c = await widget.api.create(
        brandName: _brand.text.trim(), title: _title.text.trim(), brief: _brief.text.trim(),
        deliverable: _deliverable.text.trim(), link: _link.text.trim(), feeUsdCents: cents, slots: _slots, days: _days);
      if (!mounted) return;
      if (c.awaitingPayment) {
        final link = c.paymentLink;
        if (link == null) throw Exception('The NardoPay page couldn\'t be opened. Please try again.');
        await PendingPurchase.save('campaign', c.id);
        if (!await openCheckoutPage(link)) {
          await PendingPurchase.clear();
          throw Exception('The NardoPay page couldn\'t be opened. Please try again.');
        }
      }
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => CampaignDetailScreen(campaignId: c.id, api: widget.api, waitForPayment: c.awaitingPayment)));
    } catch (e) {
      if (mounted) setState(() => _error = _err(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  InputDecoration _dec(String label, {String? hint, String? prefix}) => InputDecoration(
        labelText: label,
        hintText: hint,
        prefixText: prefix,
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
      );

  @override
  Widget build(BuildContext context) {
    final cents = _feeCents;
    final budget = cents == null ? null : cents * _slots / 100;
    final creditUsed = budget == null ? 0.0 : (_credit < budget ? _credit : budget);
    final toPay = budget == null ? null : budget - creditUsed;
    final fee = _opts.feePercent;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(backgroundColor: AppColors.background, title: const Text('New campaign')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
        TextField(controller: _brand, maxLength: 80, decoration: _dec('Brand name')),
        TextField(controller: _title, maxLength: 120, decoration: _dec('Campaign title', hint: 'e.g. Summer juice launch')),
        TextField(
            controller: _brief,
            maxLength: 2000,
            minLines: 3,
            maxLines: 8,
            decoration: _dec('Brief', hint: 'What should creators show or say? What should they avoid?')),
        TextField(controller: _deliverable, maxLength: 500, decoration: _dec('What you want from each creator')),
        TextField(controller: _link, maxLength: 300, decoration: _dec('Your website (optional)', hint: 'https://')),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _fee,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              decoration: _dec('Fee per creator', prefix: '\$ '),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonFormField<int>(
              initialValue: _slots,
              decoration: _dec('Creators'),
              items: [for (final n in const [1, 2, 3, 5, 10, 20, 50]) DropdownMenuItem(value: n, child: Text('$n'))],
              onChanged: (v) => setState(() => _slots = v ?? _slots),
            ),
          ),
        ]),
        if (_fee.text.isNotEmpty && cents == null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('The fee must be between ${usd(_opts.feeMinUsd)} and ${usd(_opts.feeMaxUsd)}.',
                style: const TextStyle(fontSize: 12, color: AppColors.danger)),
          ),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          initialValue: _days,
          decoration: _dec('Creators must post within'),
          items: [for (final d in const [7, 14, 30, 60]) DropdownMenuItem(value: d, child: Text('$d days'))],
          onChanged: (v) => setState(() => _days = v ?? _days),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: AppTheme.card(),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _line('Budget', budget == null ? '—' : usd(budget)),
            if (creditUsed > 0) _line('Campaign credit used', '−${usd(creditUsed)}'),
            _line('You pay now', toPay == null ? '—' : (toPay > 0 ? '${usd(toPay)} + fee' : '\$0'), bold: true),
            const SizedBox(height: 6),
            Text(
              [
                if (cents != null) 'Each creator gets ${usd(cents * _opts.creatorShare / 100)} (80% of the fee); VIYO keeps 20%.',
                if (toPay != null && toPay > 0 && fee != null)
                  'NardoPay adds about ${fee.toStringAsFixed(0)}% (about ${usd(toPay * fee / 100)}) at checkout.',
                'Only creators at level ${_opts.minLevel} or above can apply. Posts you don\'t decide on within '
                    '${_opts.autoApproveDays} days are approved automatically.',
                'Money not used comes back as campaign credit.',
              ].join(' '),
              style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted, height: 1.4),
            ),
          ]),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 12.5)),
          ),
        const SizedBox(height: 16),
        SizedBox(
          height: 48,
          child: ElevatedButton(
            onPressed: _valid && !_busy && (toPay == 0 || _opts.canPay) ? _submit : null,
            child: _busy
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(toPay != null && toPay > 0 ? 'Pay ${usd(toPay)} + fee by card' : 'Start campaign'),
          ),
        ),
        if (toPay != null && toPay > 0 && !_opts.canPay && _opts.available)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('Card payments aren\'t available right now.',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
          ),
      ]),
    );
  }

  Widget _line(String a, String b, {bool bold = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(children: [
          Expanded(child: Text(a, style: TextStyle(fontSize: 13, fontWeight: bold ? FontWeight.w800 : FontWeight.w400))),
          Text(b,
              style: TextStyle(
                  fontSize: 13, fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()])),
        ]),
      );
}

/// One campaign: waiting for NardoPay's confirmation, then applicants to pick and posts to approve.
class CampaignDetailScreen extends StatefulWidget {
  const CampaignDetailScreen(
      {super.key, required this.campaignId, this.api = const BrandCampaignApi(), this.waitForPayment = false});
  final String campaignId;
  final BrandCampaignApi api;
  final bool waitForPayment;

  @override
  State<CampaignDetailScreen> createState() => _CampaignDetailScreenState();
}

class _CampaignDetailScreenState extends State<CampaignDetailScreen> {
  BrandCampaign? _c;
  String? _error;
  bool _busy = false;
  int _waitToken = 0;

  @override
  void initState() {
    super.initState();
    _load().then((_) {
      if (widget.waitForPayment && (_c?.awaitingPayment ?? false)) _waitForPayment();
    });
  }

  @override
  void dispose() {
    _waitToken++;
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final c = await widget.api.detail(widget.campaignId);
      if (mounted) {
        setState(() {
          _c = c;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = _err(e));
    }
  }

  /// Back from NardoPay: keeps asking the server until the signed payment webhook has opened the campaign.
  Future<void> _waitForPayment() async {
    final token = ++_waitToken;
    for (var i = 0; i < 150 && mounted && token == _waitToken; i++) {
      await Future.delayed(const Duration(seconds: 4));
      if (!mounted || token != _waitToken) return;
      await _load();
      if (_c != null && !_c!.awaitingPayment) {
        await PendingPurchase.clear();
        return;
      }
    }
    if (mounted && token == _waitToken) await PendingPurchase.clear();
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

  Future<void> _reject(BrandApplication a) async {
    final ctrl = TextEditingController();
    final note = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Don\'t approve this post?'),
        content: TextField(
            controller: ctrl,
            maxLength: 300,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Tell the creator why')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Don\'t approve')),
        ],
      ),
    );
    if (note == null) return;
    await _do(() => widget.api.decide(a.id, 'reject', note: note), 'The creator has been told.');
  }

  Future<void> _viewPost(String id) async {
    try {
      final found = await PostService.getPostsByIds([id]);
      if (!mounted || found.isEmpty) return;
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => PostDetailScreen(post: found.first)));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('That post couldn\'t be opened.')));
      }
    }
  }

  Future<void> _close() async {
    final c = _c!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(c.awaitingPayment ? 'Cancel this campaign?' : 'Close this campaign?'),
        content: Text(c.awaitingPayment
            ? 'Nothing has been paid for it yet.'
            : 'No one new can apply. Creators you picked can still post until the deadline. Money that isn\'t '
                'used comes back as campaign credit.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep it')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(c.awaitingPayment ? 'Cancel it' : 'Close it')),
        ],
      ),
    );
    if (ok != true) return;
    await _do(() async {
      final back = await widget.api.close(c.id);
      if (back > 0 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${usd(back)} added to your campaign credit.')));
      }
    }, c.awaitingPayment ? 'Campaign cancelled.' : 'Campaign closed.');
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: const Text('Campaign'),
        actions: [
          if (c != null && (c.isOpen || c.awaitingPayment))
            TextButton(onPressed: _busy ? null : _close, child: Text(c.awaitingPayment ? 'Cancel' : 'Close')),
        ],
      ),
      body: c == null
          ? Center(
              child: _error == null
                  ? const CircularProgressIndicator()
                  : Text(_error!, style: const TextStyle(color: AppColors.textSecondary)))
          : RefreshIndicator(onRefresh: _load, child: _body(c)),
    );
  }

  Widget _body(BrandCampaign c) {
    final s = campaignStatus(c.status);
    List<BrandApplication> by(String st) => c.applications.where((a) => a.status == st).toList();
    final taken = c.applications.where((a) => const {'accepted', 'submitted', 'approved'}.contains(a.status)).length;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
      Row(children: [
        Expanded(child: Text(c.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900))),
        StatusChip(s.text, s.color),
      ]),
      const SizedBox(height: 4),
      Text('${c.brandName} · ${usd(c.feeUsd)} per creator (they get ${usd(c.creatorGetsUsd)}) · '
          '$taken of ${c.slots} picked · until ${_date(c.deadline)}',
          style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
      if (c.awaitingPayment) ...[
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: AppTheme.card(),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 10),
              Expanded(
                  child: Text('Waiting for payment confirmation (${usd(c.payUsd)} + fee)',
                      style: const TextStyle(fontWeight: FontWeight.w700))),
            ]),
            const SizedBox(height: 8),
            const Text('Your campaign opens to creators as soon as NardoPay confirms the payment.',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
            if (c.paymentLink != null) ...[
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () async {
                  await PendingPurchase.save('campaign', c.id);
                  await openCheckoutPage(c.paymentLink!);
                },
                child: const Text('Open the payment page'),
              ),
            ],
          ]),
        ),
      ],
      if (c.creditedBackUsd > 0)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text('${usd(c.creditedBackUsd)} came back to your campaign credit.',
              style: const TextStyle(fontSize: 12.5, color: AppColors.success)),
        ),
      _section('Posts to review', by('submitted'), (a) => [
            if (a.postId != null)
              TextButton.icon(
                onPressed: () => _viewPost(a.postId!),
                icon: const Icon(Icons.play_circle_outline, size: 18),
                label: const Text('View the post'),
              ),
            Text(
                a.autoApprovesAt != null
                    ? 'Approved automatically on ${_date(a.autoApprovesAt)} if you don\'t decide.'
                    : '',
                style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: _busy
                      ? null
                      : () => _do(() => widget.api.decide(a.id, 'approve'), 'Approved. The creator has been paid.'),
                  child: Text('Approve · pay ${usd(c.creatorGetsUsd)}'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(onPressed: _busy ? null : () => _reject(a), child: const Text('Don\'t approve')),
            ]),
          ]),
      _section('Applicants', by('applied'), (a) => [
            Row(children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: _busy || taken >= c.slots || !c.isOpen
                      ? null
                      : () => _do(() => widget.api.decide(a.id, 'accept'), 'Picked. The creator has been told.'),
                  child: const Text('Pick'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                  onPressed: _busy ? null : () => _do(() => widget.api.decide(a.id, 'decline'), 'Declined.'),
                  child: const Text('Decline')),
            ]),
          ]),
      _section('Making their post', by('accepted'), (_) => const []),
      _section('Done', [...by('approved'), ...by('rejected'), ...by('expired'), ...by('declined'), ...by('withdrawn')],
          (_) => const []),
      if (c.applications.isEmpty && c.isOpen)
        const Padding(
          padding: EdgeInsets.only(top: 24),
          child: Text('Creators can see your campaign now. Applications show here.',
              textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted)),
        ),
      const SizedBox(height: 18),
      Text(c.brief, style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.4)),
    ]);
  }

  Widget _section(String title, List<BrandApplication> apps, List<Widget> Function(BrandApplication) actions) {
    if (apps.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 8),
        child: Text('$title (${apps.length})', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
      ),
      for (final a in apps)
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: AppTheme.card(),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                  child: Text(a.creatorName ?? 'Creator', style: const TextStyle(fontWeight: FontWeight.w700))),
              Builder(builder: (_) {
                final s = applicationStatus(a.status);
                return StatusChip(a.autoApproved ? 'Approved automatically' : s.text, s.color);
              }),
            ]),
            if (a.pitch.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(a.pitch, style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
            ],
            if (a.decisionNote.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('Reason: ${a.decisionNote}', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
            ],
            ...actions(a),
          ]),
        ),
    ]);
  }
}
