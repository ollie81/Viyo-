import 'package:flutter/material.dart';

import '../../services/creator_studio_service.dart';
import '../../theme/app_theme.dart';
import 'novel_chapters.dart';
import 'studio_project_screen.dart';
import 'studio_widgets.dart';

/// The episode plan board: the approved novel split into episodes (which chapters each covers, its hook, turn and
/// cliffhanger), edited and approved by the creator, then created as episode productions.
class EpisodePlanScreen extends StatefulWidget {
  final String storyId;
  final ChaptersApi api;
  const EpisodePlanScreen({super.key, required this.storyId, this.api = const ChaptersApi()});
  @override
  State<EpisodePlanScreen> createState() => _EpisodePlanScreenState();
}

class _EpisodePlanScreenState extends State<EpisodePlanScreen> {
  Map<String, dynamic>? _d;
  bool _busy = false;
  final _count = TextEditingController();
  final _seconds = TextEditingController();
  final _note = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _count.dispose();
    _seconds.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final d = await widget.api.episodes(widget.storyId);
      if (!mounted) return;
      if (_count.text.isEmpty) {
        final wanted = (d['episodes_wanted'] as num?)?.toInt() ?? 0;
        _count.text = '${wanted > 0 ? wanted : (d['chapters'] as num?)?.toInt() ?? 10}';
      }
      if (_seconds.text.isEmpty) _seconds.text = '${(d['seconds'] as num?)?.toInt() ?? 90}';
      setState(() => _d = d);
    } on StudioException catch (e) {
      if (mounted) showStudioError(context, e.message);
    }
  }

  Future<void> _run(Future<Map<String, dynamic>> Function() fn, {String? done}) async {
    setState(() => _busy = true);
    try {
      final d = await fn();
      if (!mounted) return;
      setState(() => _d = {...?_d, ...d});
      if (done != null) showStudioInfo(context, done);
    } on StudioException catch (e) {
      if (!mounted) return;
      showStudioError(context, e.message);
      if (e.notEnoughCredits) await showCreditsSheet(context);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<Map<String, dynamic>> get _plan =>
      ((_d?['plan'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  Future<void> _edit(int index) async {
    final e = _plan[index];
    final title = TextEditingController(text: '${e['title'] ?? ''}');
    final summary = TextEditingController(text: '${e['summary'] ?? ''}');
    final cliff = TextEditingController(text: '${e['cliffhanger'] ?? ''}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Episode ${e['number']}'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: title, decoration: const InputDecoration(labelText: 'Title')),
            TextField(controller: summary, maxLines: 4, decoration: const InputDecoration(labelText: 'What happens')),
            TextField(controller: cliff, maxLines: 2, decoration: const InputDecoration(labelText: 'Cliffhanger')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    final changed = {...e, 'title': title.text.trim(), 'summary': summary.text.trim(), 'cliffhanger': cliff.text.trim()};
    // Disposed after the dialog's closing animation.
    Future.delayed(const Duration(seconds: 1), () {
      title.dispose();
      summary.dispose();
      cliff.dispose();
    });
    if (ok != true || !mounted) return;
    final plan = _plan..[index] = changed;
    await _run(() => widget.api.editEpisodePlan(widget.storyId, plan));
  }

  Future<void> _approve() async {
    final n = _plan.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Create $n episodes?'),
        content: const Text('Each episode becomes a production in a new series, with the novel\'s cast, places and '
            'Story Bible. This is free; writing and filming each episode is paid as usual.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Create')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _run(() => widget.api.approveEpisodePlan(widget.storyId, (_d!['version'] as num).toInt()),
        done: '$n episodes created.');
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    return Scaffold(
      appBar: AppBar(title: const Text('Episodes')),
      body: d == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(16), children: [
              if (_busy) const LinearProgressIndicator(minHeight: 2),
              ...(((d['created'] as List?) ?? const []).isNotEmpty ? _created(d) : _planning(d)),
            ]),
    );
  }

  List<Widget> _created(Map<String, dynamic> d) {
    final eps = ((d['created'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    return [
      Text('${eps.length} episodes created', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
      const Text('Open one to write its screenplay: VIYO writes it from the plan, the novel\'s own words and the '
          'story memory at that episode.', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      const SizedBox(height: 8),
      for (final e in eps)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(radius: 14, child: Text('${e['number']}', style: const TextStyle(fontSize: 12))),
          title: Text('${e['title']}', style: const TextStyle(fontSize: 14)),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => StudioProjectScreen(projectId: '${e['project_id']}'))),
        ),
    ];
  }

  List<Widget> _planning(Map<String, dynamic> d) {
    final plan = _plan;
    final problems = ((d['problems'] as List?) ?? const []).map((p) => '$p').toList();
    final price = (d['price'] as num?)?.toInt() ?? 0;
    return [
      Row(children: [
        Expanded(
          child: TextField(
              controller: _count,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Number of episodes')),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
              controller: _seconds,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Seconds per episode')),
        ),
      ]),
      TextField(
          controller: _note, maxLines: 2, decoration: const InputDecoration(labelText: 'Anything to keep in mind? (optional)')),
      const SizedBox(height: 8),
      FilledButton.icon(
        onPressed: _busy
            ? null
            : () => _run(() => widget.api.planEpisodes(widget.storyId, int.tryParse(_count.text.trim()) ?? 0,
                int.tryParse(_seconds.text.trim()) ?? 90, _note.text.trim())),
        icon: const Icon(Icons.auto_awesome, size: 18),
        label: Text('${plan.isEmpty ? 'Plan the episodes' : 'Plan again'} · up to ${creditsLabel(price)}'),
      ),
      if (problems.isNotEmpty) ...[
        const SizedBox(height: 12),
        const Text('Fix these before approving', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.danger)),
        for (final p in problems) Text('• $p', style: const TextStyle(fontSize: 13, color: AppColors.danger)),
      ],
      for (var i = 0; i < plan.length; i++) _episode(i, plan[i]),
      if (plan.isNotEmpty) ...[
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _busy || problems.isNotEmpty ? null : _approve,
          icon: const Icon(Icons.check, size: 18),
          label: Text('Approve and create ${plan.length} episodes'),
        ),
      ],
    ];
  }

  Widget _episode(int i, Map<String, dynamic> e) {
    const small = TextStyle(fontSize: 12, color: AppColors.textSecondary);
    final a = e['chapter_from'], b = e['chapter_to'];
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: AppTheme.card(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child: Text('${e['number']}. ${e['title']}', style: const TextStyle(fontWeight: FontWeight.w700))),
          Text(a == b ? 'Chapter $a' : 'Chapters $a–$b', style: small),
          IconButton(
              tooltip: 'Edit', onPressed: _busy ? null : () => _edit(i), icon: const Icon(Icons.edit, size: 18)),
        ]),
        Text('${e['summary'] ?? ''}', style: const TextStyle(fontSize: 13)),
        if ('${e['hook'] ?? ''}'.isNotEmpty) Text('Hook: ${e['hook']}', style: small),
        if ('${e['turn'] ?? ''}'.isNotEmpty) Text('Turn: ${e['turn']}', style: small),
        if ('${e['cliffhanger'] ?? ''}'.isNotEmpty) Text('Ends: ${e['cliffhanger']}', style: small),
      ]),
    );
  }
}
