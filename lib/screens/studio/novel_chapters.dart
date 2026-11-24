import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/creator_studio_service.dart';
import '../../theme/app_theme.dart';
import 'studio_widgets.dart';

/// A short label for a chapter's review in the chapter list.
String reviewLabel(String status, bool revised) => switch (status) {
      'passed' => revised ? 'review passed after a revision' : 'review passed',
      'needs_work' => 'review: needs work',
      'incomplete' => 'review incomplete',
      'unavailable' => 'not reviewed',
      _ => '',
    };

/// The server calls the chapter screens make (a fake in tests).
class ChaptersApi {
  const ChaptersApi();
  Future<Map<String, dynamic>> list(String storyId) => CreatorStudioService.storyChapters(storyId);
  Future<Map<String, dynamic>> chapter(String storyId, int n) => CreatorStudioService.storyChapter(storyId, n);
  Future<Map<String, dynamic>> write(String storyId, int n, String note) =>
      CreatorStudioService.writeChapter(storyId, n, note);
  Future<Map<String, dynamic>> approve(String storyId, int n, int version, bool withSuggestions) =>
      CreatorStudioService.approveChapter(storyId, n, version, withSuggestions);
  Future<Map<String, dynamic>> decide(
          String storyId, Map<String, List<String>> approve, Map<String, List<String>> reject) =>
      CreatorStudioService.decideMemory(storyId, approve, reject);
}

/// The novel's chapters, in order: written one at a time from the story memory, each after the one before it
/// is approved.
class NovelChaptersSection extends StatefulWidget {
  final String storyId;
  final ChaptersApi api;
  final Duration poll;
  const NovelChaptersSection(
      {super.key, required this.storyId, this.api = const ChaptersApi(), this.poll = const Duration(seconds: 5)});
  @override
  State<NovelChaptersSection> createState() => _NovelChaptersSectionState();
}

class _NovelChaptersSectionState extends State<NovelChaptersSection> {
  Map<String, dynamic>? _d;
  bool _busy = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  bool get _writing => ['queued', 'running'].contains((_d?['writing'] as Map?)?['status']);

  Future<void> _load() async {
    try {
      final d = await widget.api.list(widget.storyId);
      if (!mounted) return;
      setState(() => _d = d);
      _timer?.cancel();
      if (_writing) _timer = Timer(widget.poll, _load);
    } on StudioException catch (e) {
      if (mounted) showStudioError(context, e.message);
    }
  }

  Future<void> _write(int n) async {
    setState(() => _busy = true);
    try {
      await widget.api.write(widget.storyId, n, '');
      await _load();
    } on StudioException catch (e) {
      if (!mounted) return;
      showStudioError(context, e.message);
      if (e.notEnoughCredits) await showCreditsSheet(context);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(int n) async {
    await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => NovelChapterScreen(storyId: widget.storyId, number: n, api: widget.api)));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    if (d == null) return const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator(minHeight: 2));
    final chapters = (d['chapters'] as List? ?? const []).map((c) => Map<String, dynamic>.from(c as Map)).toList();
    final next = (d['next'] as num?)?.toInt();
    final writing = d['writing'] is Map ? Map<String, dynamic>.from(d['writing'] as Map) : null;
    final price = (d['price'] as num?)?.toInt() ?? 0;
    final written = chapters.where((c) => c['status'] != 'planned').length;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 12),
      Text('Chapters · $written of ${chapters.length} written',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
      const SizedBox(height: 6),
      if (_writing)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 8),
            Text('Writing chapter ${writing!['chapter']}…', style: const TextStyle(fontSize: 13)),
          ]),
        )
      else if (writing != null && writing['status'] == 'failed')
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text('Chapter ${writing['chapter']} wasn\'t written: ${writing['error'] ?? ''}',
              style: const TextStyle(fontSize: 12, color: AppColors.danger)),
        ),
      for (final c in chapters) _row(c, next),
      if (next != null && !_writing && !chapters.any((c) => c['number'] == next && c['status'] == 'draft'))
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: FilledButton.icon(
            onPressed: _busy ? null : () => _write(next),
            icon: const Icon(Icons.edit_note, size: 18),
            label: Text('Write chapter $next · up to ${creditsLabel(price)}'),
          ),
        ),
      if (next == null && chapters.isNotEmpty && chapters.every((c) => c['status'] == 'approved'))
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text('Every chapter is written and approved.', style: TextStyle(color: AppColors.success)),
        ),
    ]);
  }

  Widget _row(Map<String, dynamic> c, int? next) {
    final n = (c['number'] as num).toInt();
    final status = '${c['status']}';
    final issues = (c['issues'] as num?)?.toInt() ?? 0;
    final review = reviewLabel('${c['review'] ?? ''}', c['revised'] == true);
    final icon = switch (status) {
      'approved' => const Icon(Icons.check_circle, color: AppColors.success, size: 18),
      'draft' => const Icon(Icons.rate_review_outlined, color: AppColors.coin, size: 18),
      _ => const Icon(Icons.radio_button_unchecked, color: AppColors.textSecondary, size: 18),
    };
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: icon,
      title: Text('$n. ${c['title'] ?? ''}', style: const TextStyle(fontSize: 13)),
      subtitle: status == 'planned'
          ? null
          : Text(
              '${status == 'draft' ? 'Waiting for your review' : 'Approved'} · ${c['words']} words'
              '${issues > 0 ? ' · $issues continuity ${issues == 1 ? 'problem' : 'problems'}' : ''}'
              '${review.isNotEmpty ? ' · $review' : ''}',
              style: TextStyle(fontSize: 12, color: issues > 0 ? AppColors.danger : AppColors.textSecondary)),
      onTap: status == 'planned' ? null : () => _open(n),
    );
  }
}

/// One chapter: the text, the continuity problems VIYO found, and its suggestions for the story memory, each with
/// the words from the chapter that support it. The creator approves suggestions one by one or with the chapter.
class NovelChapterScreen extends StatefulWidget {
  final String storyId;
  final int number;
  final ChaptersApi api;
  const NovelChapterScreen({super.key, required this.storyId, required this.number, this.api = const ChaptersApi()});
  @override
  State<NovelChapterScreen> createState() => _NovelChapterScreenState();
}

class _NovelChapterScreenState extends State<NovelChapterScreen> {
  Map<String, dynamic>? _d;
  bool _busy = false;
  final _note = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final d = await widget.api.chapter(widget.storyId, widget.number);
      if (mounted) setState(() => _d = d);
    } on StudioException catch (e) {
      if (mounted) showStudioError(context, e.message);
    }
  }

  Future<void> _do(Future<void> Function() fn) async {
    setState(() => _busy = true);
    try {
      await fn();
      await _load();
    } on StudioException catch (e) {
      if (!mounted) return;
      showStudioError(context, e.message);
      if (e.notEnoughCredits) await showCreditsSheet(context);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _approve(bool withSuggestions) => _do(() async {
        final c = Map<String, dynamic>.from(_d!['chapter'] as Map);
        final r =
            await widget.api.approve(widget.storyId, widget.number, (c['version'] as num).toInt(), withSuggestions);
        if (!mounted) return;
        final skipped = (r['skipped'] as List?) ?? const [];
        showStudioInfo(
            context,
            'Chapter ${widget.number} approved'
            '${withSuggestions ? ' with ${r['approved_suggestions']} suggestions' : ''}'
            '${skipped.isNotEmpty ? '. ${skipped.length} skipped: they contradict facts you locked.' : '.'}');
      });

  Future<void> _decide(String kind, String id, bool keep) => _do(() => widget.api.decide(
      widget.storyId,
      keep
          ? {
              kind: [id]
            }
          : {},
      keep
          ? {}
          : {
              kind: [id]
            }));

  @override
  Widget build(BuildContext context) {
    final d = _d;
    return Scaffold(
      appBar: AppBar(title: Text('Chapter ${widget.number}')),
      body: d == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(16), children: _body(d)),
    );
  }

  List<Widget> _body(Map<String, dynamic> d) {
    final c = Map<String, dynamic>.from(d['chapter'] as Map);
    final ex = Map<String, dynamic>.from((c['extraction'] as Map?) ?? const {});
    final s = Map<String, dynamic>.from((d['suggestions'] as Map?) ?? const {});
    final issues = (ex['issues'] as List?) ?? const [];
    final approved = c['status'] == 'approved';
    const head = TextStyle(fontWeight: FontWeight.w700, fontSize: 14);
    return [
      if (_busy) const LinearProgressIndicator(minHeight: 2),
      Text('${c['title']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
      Text('Version ${c['version']} · ${c['words']} words · ${approved ? 'approved' : 'waiting for your review'}',
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      const SizedBox(height: 12),
      ..._review(Map<String, dynamic>.from((c['review_report'] as Map?) ?? const {})),
      if (issues.isNotEmpty) ...[
        const Text('Continuity problems', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.danger)),
        for (final i in issues.map((x) => Map<String, dynamic>.from(x as Map)))
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('• ${i['reason']}${'${i['quote'] ?? ''}'.isNotEmpty ? '  “${i['quote']}”' : ''}',
                style: const TextStyle(fontSize: 13, color: AppColors.danger)),
          ),
        const SizedBox(height: 12),
      ],
      SelectableText('${c['text']}', style: const TextStyle(fontSize: 15, height: 1.6)),
      const SizedBox(height: 20),
      for (final kind in const ['facts', 'events', 'threads'])
        if (((s[kind] as List?) ?? const []).isNotEmpty) ...[
          Text(
              {
                'facts': 'Suggested facts for the story memory',
                'events': 'Suggested events',
                'threads': 'Suggested threads to pay off later'
              }[kind]!,
              style: head),
          for (final x in (s[kind] as List).map((v) => Map<String, dynamic>.from(v as Map))) _suggestion(kind, x),
          const SizedBox(height: 12),
        ],
      if (!approved) ...[
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.icon(
            onPressed: _busy ? null : () => _approve(true),
            icon: const Icon(Icons.done_all, size: 18),
            label: const Text('Approve chapter and suggestions'),
          ),
          OutlinedButton(
            onPressed: _busy ? null : () => _approve(false),
            child: const Text('Approve chapter only'),
          ),
        ]),
        const SizedBox(height: 16),
        TextField(
          controller: _note,
          minLines: 1,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'What should change? (for a new version)'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _busy ? null : () => _do(() => widget.api.write(widget.storyId, widget.number, _note.text.trim())),
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Write a new version'),
        ),
      ],
    ];
  }

  static const _areaLabels = {
    'originality': 'Originality',
    'character': 'Character development',
    'emotion': 'Emotional depth',
    'plot': 'Plot coherence',
    'dialogue': 'Dialogue',
    'prose': 'Literary quality',
    'cinematic': 'Cinematic potential',
    'opening': 'Opening',
    'ending': 'Ending',
  };

  /// VIYO's own review: every score with the words it's based on, what's weak and why, and what happened to the
  /// one targeted revision.
  List<Widget> _review(Map<String, dynamic> r) {
    if (r.isEmpty) return const [];
    final cats = Map<String, dynamic>.from((r['categories'] as Map?) ?? const {});
    final rev = r['revision'] is Map ? Map<String, dynamic>.from(r['revision'] as Map) : null;
    final weak = (r['weak'] as List?) ?? const [];
    final color = switch ('${r['status']}') {
      'passed' => AppColors.success,
      'needs_work' => AppColors.coin,
      _ => AppColors.textSecondary,
    };
    return [
      Container(
        decoration: studioPanel(border: color.withValues(alpha: 0.5)),
        child: Material(
          type: MaterialType.transparency,
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 12),
            childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            leading: Icon(Icons.fact_check_outlined, color: color),
            title: Text("VIYO's review", style: TextStyle(fontWeight: FontWeight.w700, color: color)),
            subtitle: Text('${r['summary'] ?? ''}', style: const TextStyle(fontSize: 12)),
            children: [
              if (rev != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                      rev['kept'] == true
                          ? 'VIYO rewrote passage ${(rev['passages'] as List).join(', ')} and kept it: ${rev['why']}.'
                          : 'Not rewritten: ${rev['why']}.',
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                ),
              for (final e in cats.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: _area(e.key, Map<String, dynamic>.from(e.value as Map)),
                ),
              if (weak.isNotEmpty) ...[
                const SizedBox(height: 4),
                const Text('What could be stronger', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                for (final w in weak.map((x) => Map<String, dynamic>.from(x as Map)))
                  Text('• ${_areaLabels[w['area']] ?? w['area']}: ${w['why']} Fix: ${w['fix']}',
                      style: const TextStyle(fontSize: 12)),
              ],
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
    ];
  }

  Widget _area(String key, Map<String, dynamic> a) {
    final verified = a['status'] == 'verified';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(
          verified
              ? '${_areaLabels[key] ?? key}: ${a['score']}/10 — ${a['reason'] ?? ''}'
              : '${_areaLabels[key] ?? key}: not counted (${a['why'] ?? ''})',
          style: TextStyle(fontSize: 12, color: verified ? null : AppColors.textSecondary)),
      if (verified && '${a['quote'] ?? ''}'.isNotEmpty)
        Text('“${a['quote']}”',
            style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: AppColors.textSecondary)),
    ]);
  }

  Widget _suggestion(String kind, Map<String, dynamic> x) {
    final conflicts = (x['conflicts'] as List?) ?? const [];
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${x['statement']}', style: const TextStyle(fontSize: 13)),
            if ('${x['quote'] ?? ''}'.isNotEmpty)
              Text('“${x['quote']}”',
                  style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: AppColors.textSecondary)),
            if (conflicts.isNotEmpty)
              Text('Conflicts: ${conflicts.join(', ')}', style: const TextStyle(fontSize: 12, color: AppColors.danger)),
          ]),
        ),
        IconButton(
          tooltip: 'Keep',
          onPressed: _busy ? null : () => _decide(kind, '${x['id']}', true),
          icon: const Icon(Icons.check, color: AppColors.success),
        ),
        IconButton(
          tooltip: 'Reject',
          onPressed: _busy ? null : () => _decide(kind, '${x['id']}', false),
          icon: const Icon(Icons.close, color: AppColors.danger),
        ),
      ]),
    );
  }
}
