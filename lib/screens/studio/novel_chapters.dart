import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/creator_studio_service.dart';
import '../../theme/app_theme.dart';
import 'episode_plan_screen.dart';
import 'story_bible_screen.dart';
import 'studio_widgets.dart';

/// VIYO's opinion of a continuity problem, in plain words (it never decides).
String verdictLabel(String verdict) => switch (verdict) {
      'error' => 'VIYO thinks this is a mistake',
      'intended' => 'VIYO thinks this is deliberate',
      'unclear' => "VIYO isn't sure",
      _ => '',
    };

/// What the creator decided about a continuity problem.
String resolutionLabel(String action) => switch (action) {
      'fix_chapter' => 'To fix in a new version',
      'chapter_right' => 'The chapter is right: the memory was updated',
      'intended' => 'Marked as intentional',
      _ => '',
    };

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
  Future<Map<String, dynamic>> approve(String storyId, int n, int version, bool withSuggestions,
          {bool acceptProblems = false}) =>
      CreatorStudioService.approveChapter(storyId, n, version, withSuggestions, acceptProblems: acceptProblems);
  Future<Map<String, dynamic>> decideProblem(String storyId, int n, int version, String problemId, String action,
          {String reason = '', bool untilEnd = false, bool unlock = false}) =>
      CreatorStudioService.decideProblem(storyId, n, version, problemId, action,
          reason: reason, untilEnd: untilEnd, unlock: unlock);
  Future<Map<String, dynamic>> approveNovel(String storyId, int chapters, {bool acceptProblems = false}) =>
      CreatorStudioService.approveNovel(storyId, chapters, acceptProblems: acceptProblems);
  Future<Map<String, dynamic>> bible(String storyId) => CreatorStudioService.storyBible(storyId);
  Future<Map<String, dynamic>> episodes(String storyId) => CreatorStudioService.episodePlan(storyId);
  Future<Map<String, dynamic>> planEpisodes(String storyId, int episodes, int seconds, String note) =>
      CreatorStudioService.planEpisodes(storyId, episodes, seconds, note);
  Future<Map<String, dynamic>> editEpisodePlan(String storyId, List<Map<String, dynamic>> episodes) =>
      CreatorStudioService.editEpisodePlan(storyId, episodes);
  Future<Map<String, dynamic>> approveEpisodePlan(String storyId, int version) =>
      CreatorStudioService.approveEpisodePlan(storyId, version);
  Future<Map<String, dynamic>> syncBible(String storyId) => CreatorStudioService.syncStoryBible(storyId);
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

  Future<void> _openBible() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => StoryBibleScreen(storyId: widget.storyId, api: widget.api)));
    await _load();
  }

  Future<void> _approveNovel(int chapters, {bool acceptProblems = false}) async {
    if (!acceptProblems) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Approve the whole novel?'),
          content: const Text('Its story memory becomes the production\'s Story Bible, and its characters, places and '
              'objects join the production. This is free. Chapters can\'t be rewritten after this.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Approve')),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    setState(() => _busy = true);
    String? problems;
    try {
      final r = await widget.api.approveNovel(widget.storyId, chapters, acceptProblems: acceptProblems);
      final b = Map<String, dynamic>.from((r['bible'] as Map?) ?? const {});
      if (mounted) {
        showStudioInfo(
            context,
            'Novel approved. ${b['characters_created'] ?? 0} characters and ${b['elements_created'] ?? 0} places '
            'and objects were added to the production.');
      }
      await _load();
    } on StudioException catch (e) {
      if (e.code == 'memory_problems') {
        problems = e.message;
      } else if (mounted) {
        showStudioError(context, e.message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (problems != null && mounted) {
      final yes = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Approve anyway?'),
          content: Text('$problems\n\nYou can look at them in the Story Bible first.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Approve anyway')),
          ],
        ),
      );
      if (yes == true) await _approveNovel(chapters, acceptProblems: true);
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
      if (d['stage'] == 'novel_approved')
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('The novel is approved. Its Story Bible is the production\'s story.',
                style: TextStyle(color: AppColors.success)),
            const SizedBox(height: 6),
            FilledButton.icon(
              onPressed: _busy
                  ? null
                  : () async {
                      await Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => EpisodePlanScreen(storyId: widget.storyId, api: widget.api)));
                      await _load();
                    },
              icon: const Icon(Icons.movie_filter_outlined, size: 18),
              label: const Text('Turn it into episodes'),
            ),
          ]),
        )
      else if (next == null && chapters.isNotEmpty && chapters.every((c) => c['status'] == 'approved'))
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Every chapter is written and approved.', style: TextStyle(color: AppColors.success)),
            const SizedBox(height: 6),
            FilledButton.icon(
              onPressed: _busy ? null : () => _approveNovel(chapters.length),
              icon: const Icon(Icons.verified_outlined, size: 18),
              label: const Text('Approve the novel'),
            ),
          ]),
        ),
      if (chapters.any((c) => c['status'] == 'approved'))
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: OutlinedButton.icon(
            onPressed: _busy ? null : _openBible,
            icon: const Icon(Icons.menu_book_outlined, size: 18),
            label: const Text('Story Bible'),
          ),
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
  String _lastFix = '';

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
      final fix = '${d['fix_note'] ?? ''}';
      if (fix.isNotEmpty && (_note.text.isEmpty || _note.text == _lastFix)) _note.text = fix;
      _lastFix = fix;
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

  int get _version => ((Map<String, dynamic>.from(_d!['chapter'] as Map))['version'] as num).toInt();

  Future<void> _approve(bool withSuggestions, {bool acceptProblems = false}) async {
    Map<String, dynamic>? r;
    String? needsConfirm;
    await _do(() async {
      try {
        r = await widget.api
            .approve(widget.storyId, widget.number, _version, withSuggestions, acceptProblems: acceptProblems);
      } on StudioException catch (e) {
        if (e.code != 'open_problems' || acceptProblems) rethrow;
        needsConfirm = e.message;
      }
    });
    if (!mounted) return;
    if (needsConfirm != null) {
      final yes = await _confirm('Approve anyway?',
          '$needsConfirm\n\nThe problems stay on record. Later chapters are written from the approved memory.');
      if (yes == true) await _approve(withSuggestions, acceptProblems: true);
      return;
    }
    final res = r;
    if (res == null) return;
    final skipped = (res['skipped'] as List?) ?? const [];
    showStudioInfo(
        context,
        'Chapter ${widget.number} approved'
        '${withSuggestions ? ' with ${res['approved_suggestions']} suggestions' : ''}'
        '${skipped.isNotEmpty ? '. ${skipped.length} skipped: they contradict facts you locked.' : '.'}');
  }

  Future<bool?> _confirm(String title, String body) => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Yes')),
          ],
        ),
      );

  Future<void> _settle(Map<String, dynamic> p, String action) async {
    final id = '${p['id']}';
    if (action == 'intended') {
      // Ask first, then save (no progress bar behind the dialog).
      final j = Map<String, dynamic>.from((p['judgement'] as Map?) ?? const {});
      final got = await showDialog<(String, bool)>(
          context: context,
          builder: (_) => _IntendedDialog(initial: '${j['verdict']}' == 'intended' ? '${j['why'] ?? ''}' : ''));
      if (got == null || !mounted) return;
      final (reason, untilEnd) = got;
      return _do(() => widget.api
          .decideProblem(widget.storyId, widget.number, _version, id, action, reason: reason, untilEnd: untilEnd));
    }
    var unlock = false;
    while (mounted) {
      try {
        await _do(() async {
          try {
            await widget.api.decideProblem(widget.storyId, widget.number, _version, id, action, unlock: unlock);
          } on StudioException catch (e) {
            if (e.code == 'confirm_unlock' && !unlock) throw _NeedsUnlock(e.message);
            rethrow;
          }
        });
        return;
      } on _NeedsUnlock catch (e) {
        if (!mounted) return;
        final yes = await _confirm('Replace a locked fact?',
            '${e.message}\n\nThe memory will follow this chapter from now on. Earlier chapters are not changed.');
        if (yes != true) return;
        unlock = true;
      }
    }
  }

  Widget _problem(Map<String, dynamic> p, bool approved) {
    final j = Map<String, dynamic>.from((p['judgement'] as Map?) ?? const {});
    final res = Map<String, dynamic>.from((p['resolution'] as Map?) ?? const {});
    final actions = ((p['actions'] as List?) ?? const []).map((a) => '$a').toList();
    const small = TextStyle(fontSize: 12, color: AppColors.textSecondary);
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: AppTheme.card(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${p['reason']}', style: const TextStyle(fontSize: 13, color: AppColors.danger)),
        if ('${p['quote'] ?? ''}'.isNotEmpty) Text('This chapter: “${p['quote']}”', style: small),
        if ('${p['memory_statement'] ?? ''}'.isNotEmpty)
          Text('The memory: ${p['memory_statement']}${p['memory_locked'] == true ? ' (locked by you)' : ''}',
              style: small),
        if (j.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(verdictLabel('${j['verdict']}'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          if ('${j['why'] ?? ''}'.isNotEmpty) Text('${j['why']}', style: small),
          if ('${j['quote'] ?? ''}'.isNotEmpty) Text('“${j['quote']}”', style: small),
        ],
        const SizedBox(height: 6),
        if (res.isNotEmpty)
          Text('✓ ${resolutionLabel('${res['action']}')}',
              style: const TextStyle(fontSize: 12, color: AppColors.success, fontWeight: FontWeight.w600))
        else if (!approved)
          Wrap(spacing: 8, runSpacing: 4, children: [
            if (actions.contains('fix_chapter'))
              OutlinedButton(
                  onPressed: _busy ? null : () => _settle(p, 'fix_chapter'), child: const Text('Fix the chapter')),
            if (actions.contains('chapter_right'))
              OutlinedButton(
                  onPressed: _busy ? null : () => _settle(p, 'chapter_right'),
                  child: const Text('The chapter is right')),
            if (actions.contains('intended'))
              OutlinedButton(
                  onPressed: _busy ? null : () => _settle(p, 'intended'), child: const Text("It's intentional")),
          ]),
      ]),
    );
  }

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
    final s = Map<String, dynamic>.from((d['suggestions'] as Map?) ?? const {});
    final problems = ((d['problems'] as List?) ?? const []).map((x) => Map<String, dynamic>.from(x as Map)).toList();
    final approved = c['status'] == 'approved';
    const head = TextStyle(fontWeight: FontWeight.w700, fontSize: 14);
    return [
      if (_busy) const LinearProgressIndicator(minHeight: 2),
      Text('${c['title']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
      Text('Version ${c['version']} · ${c['words']} words · ${approved ? 'approved' : 'waiting for your review'}',
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      const SizedBox(height: 12),
      ..._review(Map<String, dynamic>.from((c['review_report'] as Map?) ?? const {})),
      if (problems.isNotEmpty) ...[
        const Text('Continuity problems', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.danger)),
        if (!approved)
          const Text('Decide each one. VIYO gives its opinion, but you decide.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        for (final p in problems) _problem(p, approved),
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

/// The server asked the creator to confirm replacing a fact they locked.
class _NeedsUnlock implements Exception {
  final String message;
  _NeedsUnlock(this.message);
}

/// Asks why a continuity problem is deliberate, and whether that holds for the rest of the story.
class _IntendedDialog extends StatefulWidget {
  final String initial;
  const _IntendedDialog({required this.initial});
  @override
  State<_IntendedDialog> createState() => _IntendedDialogState();
}

class _IntendedDialogState extends State<_IntendedDialog> {
  late final _why = TextEditingController(text: widget.initial);
  bool _untilEnd = false;

  @override
  void dispose() {
    _why.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text("It's intentional"),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: _why,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Why? (e.g. her ghost visits Amani)')),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _untilEnd,
            onChanged: (v) => setState(() => _untilEnd = v ?? false),
            title: const Text('Also for the rest of the story', style: TextStyle(fontSize: 13)),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, (_why.text.trim(), _untilEnd)), child: const Text('Save')),
        ],
      );
}
