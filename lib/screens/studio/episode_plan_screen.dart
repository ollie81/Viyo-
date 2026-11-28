import 'package:flutter/material.dart';

import '../../services/creator_studio_service.dart';
import '../../theme/app_theme.dart';
import 'feature_screen.dart';
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
  final _minutes = TextEditingController(text: '30');
  bool _feature = false;

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
    _minutes.dispose();
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
      setState(() {
        _d = d;
        _feature = d['format'] == 'feature';
        if (d['feature_minutes'] != null) _minutes.text = '${d['feature_minutes']}';
      });
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
    final feature = _d?['format'] == 'feature';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(feature ? 'Create the feature film in $n parts?' : 'Create $n episodes?'),
        content: Text(feature
            ? 'The movie and its $n parts become productions with the novel\'s cast, places and Story Bible. This is '
                'free; writing and filming each part is paid as usual, and the parts are joined into one film at the end.'
            : 'Each episode becomes a production in a new series, with the novel\'s cast, places and '
                'Story Bible. This is free; writing and filming each episode is paid as usual.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Create')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _run(() => widget.api.approveEpisodePlan(widget.storyId, (_d!['version'] as num).toInt()),
        done: feature ? 'The feature film and its $n parts are created.' : '$n episodes created.');
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    return Scaffold(
      appBar: AppBar(title: Text(d?['format'] == 'feature' ? 'Feature film' : 'Episodes')),
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
    final featureId = d['feature_id'] ?? (d['feature'] as Map?)?['id'];
    if (featureId != null) {
      return [
        Text('Feature film in ${eps.length} parts', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => FeatureScreen(featureId: '$featureId'))),
          icon: const Icon(Icons.movie_outlined, size: 18),
          label: const Text('Open the movie'),
        ),
      ];
    }
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
      SegmentedButton<bool>(
        segments: const [
          ButtonSegment(value: false, label: Text('Episodes'), icon: Icon(Icons.view_list_outlined, size: 18)),
          ButtonSegment(value: true, label: Text('Feature film'), icon: Icon(Icons.movie_outlined, size: 18)),
        ],
        selected: {_feature},
        onSelectionChanged: _busy ? null : (v) => setState(() => _feature = v.first),
      ),
      const SizedBox(height: 10),
      if (_feature) ...[
        TextField(
            controller: _minutes,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
                labelText: 'Length of the movie (minutes, 15 to 90)', helperText: _partsText())),
      ] else
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
            : () => _run(() => _feature
                ? widget.api.planFeature(widget.storyId, int.tryParse(_minutes.text.trim()) ?? 30, _note.text.trim())
                : widget.api.planEpisodes(widget.storyId, int.tryParse(_count.text.trim()) ?? 0,
                    int.tryParse(_seconds.text.trim()) ?? 90, _note.text.trim())),
        icon: const Icon(Icons.auto_awesome, size: 18),
        label: Text('${plan.isEmpty ? (_feature ? 'Plan the movie' : 'Plan the episodes') : 'Plan again'} · up to '
            '${creditsLabel(price)}'),
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
          label: Text(d['format'] == 'feature'
              ? 'Approve and create the movie (${plan.length} parts)'
              : 'Approve and create ${plan.length} episodes'),
        ),
      ],
    ];
  }

  /// "3 parts of about 10 minutes": the same split the server makes (studio_feature.parts_for).
  String _partsText() {
    final m = (int.tryParse(_minutes.text.trim()) ?? 30).clamp(15, 90);
    final n = (m / 10).ceil();
    return '$n parts of about ${(m / n).round()} minutes, joined into one film. Feature films are new: try a short '
        'one first.';
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
