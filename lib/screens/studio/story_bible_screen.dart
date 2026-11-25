import 'package:flutter/material.dart';

import '../../services/creator_studio_service.dart';
import '../../theme/app_theme.dart';
import 'novel_chapters.dart';
import 'studio_widgets.dart';

/// The Story Bible: everything the story memory holds as approved, the way the episodes will use it. Characters
/// (as the novel ends), secrets and who knows them, places, objects, threads and the timeline.
class StoryBibleScreen extends StatefulWidget {
  final String storyId;
  final ChaptersApi api;
  const StoryBibleScreen({super.key, required this.storyId, this.api = const ChaptersApi()});
  @override
  State<StoryBibleScreen> createState() => _StoryBibleScreenState();
}

class _StoryBibleScreenState extends State<StoryBibleScreen> {
  Map<String, dynamic>? _d;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await widget.api.bible(widget.storyId);
      if (mounted) setState(() => _d = d);
    } on StudioException catch (e) {
      if (mounted) showStudioError(context, e.message);
    }
  }

  Future<void> _sync() async {
    setState(() => _busy = true);
    try {
      final r = await widget.api.syncBible(widget.storyId);
      final b = Map<String, dynamic>.from((r['bible'] as Map?) ?? const {});
      if (mounted) {
        showStudioInfo(context,
            'The production now follows the memory. ${b['characters_created'] ?? 0} new characters were added.');
      }
      await _load();
    } on StudioException catch (e) {
      if (mounted) showStudioError(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<Map<String, dynamic>> _list(String key) =>
      ((_d?[key] as List?) ?? const []).map((x) => Map<String, dynamic>.from(x as Map)).toList();

  @override
  Widget build(BuildContext context) {
    final d = _d;
    return Scaffold(
      appBar: AppBar(title: const Text('Story Bible')),
      body: d == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(16), children: [
              if (_busy) const LinearProgressIndicator(minHeight: 2),
              Text(
                  d['approved'] == true
                      ? 'The novel is approved: episodes are written from this.'
                      : 'Built from the chapters you approved so far.',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              if (d['approved'] == true)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _busy ? null : _sync,
                    icon: const Icon(Icons.sync, size: 18),
                    label: const Text('Update the production from the memory'),
                  ),
                ),
              ..._problems(),
              _section('Characters', _list('characters').map(_character).toList()),
              _section('Secrets', _list('secrets').map(_secret).toList()),
              _section('Places', _list('places').map((p) => _line(p['name'], p['description'])).toList()),
              _section(
                  'Objects',
                  _list('objects')
                      .map((o) => _line(o['name'],
                          [o['description'], if ('${o['where'] ?? ''}'.isNotEmpty) 'Now at ${o['where']}'].join(' · ')))
                      .toList()),
              _section('Threads', _list('threads').map(_thread).toList()),
              _section(
                  'Timeline',
                  _list('timeline')
                      .map((e) => _line('Chapter ${e['chapter']}',
                          '${e['summary']}${'${e['story_time'] ?? ''}'.isNotEmpty ? ' (${e['story_time']})' : ''}'))
                      .toList()),
            ]),
    );
  }

  List<Widget> _problems() {
    final probs = _list('memory_problems');
    if (probs.isEmpty) return const [];
    return [
      const SizedBox(height: 8),
      const Text('The memory disagrees with itself', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.danger)),
      for (final p in probs)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('• ${p['subject'] ?? ''}: ${p['reason']}',
              style: const TextStyle(fontSize: 13, color: AppColors.danger)),
        ),
    ];
  }

  Widget _section(String title, List<Widget> children) => Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 4),
          if (children.isEmpty)
            const Text('Nothing yet.', style: TextStyle(fontSize: 12, color: AppColors.textSecondary))
          else
            ...children,
        ]),
      );

  Widget _line(Object? title, Object? body) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$title', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          if ('${body ?? ''}'.isNotEmpty)
            Text('$body', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        ]),
      );

  Widget _character(Map<String, dynamic> c) {
    final status = '${c['status'] ?? 'alive'}';
    final rel = ((c['relationships'] as List?) ?? const []).map((r) => Map<String, dynamic>.from(r as Map));
    final facts = [
      for (final k in const ['role', 'age', 'look', 'wants', 'hides', 'arc'])
        if ('${c[k] ?? ''}'.isNotEmpty) '${_labels[k]}: ${c[k]}',
    ];
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: AppTheme.card(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('${c['name']}', style: const TextStyle(fontWeight: FontWeight.w700))),
          if (status != 'alive')
            Text(status, style: const TextStyle(fontSize: 12, color: AppColors.danger, fontWeight: FontWeight.w600)),
          if (c['has_locked_facts'] == true)
            const Padding(
                padding: EdgeInsets.only(left: 6),
                child: Tooltip(message: 'You locked some facts', child: Icon(Icons.lock_outline, size: 16))),
          if (c['cast_id'] != null)
            const Padding(
                padding: EdgeInsets.only(left: 6),
                child: Tooltip(message: 'In the production cast', child: Icon(Icons.theater_comedy_outlined, size: 16))),
        ]),
        if ('${c['where'] ?? ''}'.isNotEmpty)
          Text('At ${c['where']}', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        for (final f in facts) Text(f, style: const TextStyle(fontSize: 12)),
        for (final r in rel)
          Text('${r['with']} — ${r['kind']}: ${r['what']}',
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      ]),
    );
  }

  static const _labels = {
    'role': 'Role',
    'age': 'Age',
    'look': 'Looks',
    'wants': 'Wants',
    'hides': 'Hides',
    'arc': 'Arc',
  };

  Widget _secret(Map<String, dynamic> s) {
    final who = ((s['known_by'] as List?) ?? const [])
        .map((k) => Map<String, dynamic>.from(k as Map))
        .map((k) => '${k['who']} (${(k['since_chapter'] as num? ?? 0) == 0 ? 'from the start' : 'from chapter ${k['since_chapter']}'})')
        .toList();
    return _line(s['name'], who.isEmpty ? 'Nobody knows yet' : 'Known by ${who.join(', ')}');
  }

  Widget _thread(Map<String, dynamic> t) {
    final state = '${t['state']}';
    final where = state == 'resolved'
        ? 'planted in chapter ${t['planted_chapter']}, paid off in chapter ${t['resolved_chapter']}'
        : state == 'dropped'
            ? 'dropped'
            : 'open since chapter ${t['planted_chapter']}';
    return _line('${t['description']}', '${t['kind']} · $where');
  }
}
