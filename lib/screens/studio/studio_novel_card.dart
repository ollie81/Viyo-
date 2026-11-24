import 'package:flutter/material.dart';

import '../../services/creator_studio_service.dart';
import '../../theme/app_theme.dart';
import 'novel_chapters.dart';
import 'studio_widgets.dart';

/// The server calls the novel card makes (a fake in tests).
class NovelApi {
  const NovelApi();
  Future<Map<String, dynamic>?> load(String projectId) => CreatorStudioService.projectStory(projectId);
  Future<Map<String, dynamic>> start(String projectId, String idea, String length, int episodes) =>
      CreatorStudioService.startStory(projectId, idea, length, episodes);
  Future<Map<String, dynamic>> interview(String storyId, {String? answer, bool skip = false, bool finish = false}) =>
      CreatorStudioService.storyInterview(storyId, answer: answer, skip: skip, finish: finish);
  Future<Map<String, dynamic>> outline(String storyId, String note) => CreatorStudioService.planOutline(storyId, note);
  Future<Map<String, dynamic>> approve(String storyId, int version) =>
      CreatorStudioService.approveOutline(storyId, version);
}

/// Novel-first production: the creator's idea, a short interview (one question at a time, only what VIYO
/// doesn't know yet), a plan for the whole novel, and the creator's approval, which puts the characters,
/// places, secrets and planned threads into the story memory.
class StudioNovelCard extends StatefulWidget {
  final String projectId;
  final String logline;
  final NovelApi api;
  final ChaptersApi chaptersApi;
  const StudioNovelCard(
      {super.key,
      required this.projectId,
      this.logline = '',
      this.api = const NovelApi(),
      this.chaptersApi = const ChaptersApi()});
  @override
  State<StudioNovelCard> createState() => _StudioNovelCardState();
}

class _StudioNovelCardState extends State<StudioNovelCard> {
  Map<String, dynamic>? _story;
  bool _loaded = false, _busy = false;
  String _length = 'standard';
  late final _idea = TextEditingController(text: widget.logline);
  final _episodes = TextEditingController(text: '0');
  final _answer = TextEditingController();
  final _note = TextEditingController();
  Map<String, dynamic>? _memory;

  static const _lengths = {
    'short': 'Short · 12 chapters',
    'standard': 'Novel · 24 chapters',
    'long': 'Long · 36 chapters'
  };
  static const _topicLabels = {
    'protagonist': 'Main character',
    'goal': 'What they want',
    'genre_tone': 'Genre & tone',
    'feeling': 'How it should feel',
    'setting': 'Where & when',
    'ending': 'Ending',
    'audience': 'Audience',
    'avoid': 'Avoid',
    'relationships': 'Who matters',
    'twist': 'Twist',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _idea.dispose();
    _episodes.dispose();
    _answer.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final s = await widget.api.load(widget.projectId);
      if (mounted) {
        setState(() {
          _story = s;
          _loaded = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  Future<void> _run(Future<Map<String, dynamic>> Function() call, {bool clearAnswer = false}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final s = await call();
      if (!mounted) return;
      setState(() {
        if (s.containsKey('story') && s['story'] is Map) {
          _story = Map<String, dynamic>.from(s['story'] as Map);
          _memory = s['memory'] is Map ? Map<String, dynamic>.from(s['memory'] as Map) : null;
        } else {
          _story = s;
        }
        if (clearAnswer) _answer.clear();
      });
    } on StudioException catch (e) {
      if (!mounted) return;
      showStudioError(context, e.message);
      if (e.notEnoughCredits) await showCreditsSheet(context);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Map<String, dynamic> _m(Object? v) => v is Map ? Map<String, dynamic>.from(v) : {};
  List _l(Object? v) => v is List ? v : const [];
  String _s(Object? v) => v == null ? '' : '$v';

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    final s = _story;
    final stage = _s(s?['stage']);
    return Container(
      decoration: studioPanel(),
      child: Material(
        type: MaterialType.transparency, // so taps show on the panel
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: s == null || stage != 'outline_approved',
            tilePadding: const EdgeInsets.symmetric(horizontal: 14),
            childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            leading: const Icon(Icons.menu_book_outlined, color: AppColors.secondary),
            title: const Text('Novel', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(
                switch (stage) {
                  'interview' => 'VIYO is getting to know your story.',
                  'outline' => 'Your novel plan is ready to review.',
                  'outline_approved' => 'Plan approved · ${_s(_m(s?['outline'])['title'])}',
                  _ => 'Start from your idea: VIYO asks a few questions, then plans the whole novel.',
                },
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_busy) const LinearProgressIndicator(minHeight: 2),
              if (s == null) ..._startForm(),
              if (stage == 'interview') ..._interview(s!),
              if (stage == 'outline' || stage == 'outline_approved') ..._outline(s!),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _startForm() => [
        const SizedBox(height: 4),
        TextField(
          controller: _idea,
          minLines: 3,
          maxLines: 6,
          maxLength: 4000,
          decoration: const InputDecoration(labelText: 'Your idea, in your own words'),
        ),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final e in _lengths.entries)
            ChoiceChip(
              label: Text(e.value, style: const TextStyle(fontSize: 12)),
              selected: _length == e.key,
              onSelected: (_) => setState(() => _length = e.key),
            ),
        ]),
        const SizedBox(height: 8),
        SizedBox(
          width: 220,
          child: TextField(
            controller: _episodes,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Drama episodes later (0 = not sure)'),
          ),
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: _busy || _idea.text.trim().length < 10
              ? null
              : () => _run(() => widget.api.start(widget.projectId, _idea.text.trim(), _length,
                  (int.tryParse(_episodes.text.trim()) ?? 0).clamp(0, 200))),
          icon: const Icon(Icons.auto_stories_outlined, size: 18),
          label: const Text('Start my novel (free)'),
        ),
      ];

  List<Widget> _interview(Map<String, dynamic> s) {
    final iv = _m(s['interview']);
    final q = iv['question'] is Map ? _m(iv['question']) : null;
    final known = _m(iv['known']);
    final price = (_m(s['prices'])['question'] as num?)?.toInt() ?? 0;
    final outlinePrice = (_m(s['prices'])['outline'] as num?)?.toInt() ?? 0;
    return [
      Text('Your idea: ${_s(s['idea'])}', style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
      const SizedBox(height: 10),
      if (known.isNotEmpty) ...[
        const Text('What VIYO understood (from your words)',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 4),
        for (final e in known.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('• ${_topicLabels[e.key] ?? e.key}: ${_s(_m(e.value)['value'])}',
                style: const TextStyle(fontSize: 13)),
          ),
        const SizedBox(height: 8),
      ],
      if (q != null) ...[
        Text(_s(q['text']), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        if (_s(q['why']).isNotEmpty)
          Text(_s(q['why']), style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final o in _l(q['options']))
            ActionChip(label: Text(_s(o), style: const TextStyle(fontSize: 12)), onPressed: () => _answer.text = _s(o)),
        ]),
        TextField(
            controller: _answer, minLines: 1, maxLines: 4, decoration: const InputDecoration(labelText: 'Your answer')),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton(
            onPressed: _busy
                ? null
                : () => _run(() => widget.api.interview(_s(s['id']), answer: _answer.text.trim()), clearAnswer: true),
            child: Text('Answer · next question ~${creditsLabel(price)}'),
          ),
          OutlinedButton(
            onPressed:
                _busy ? null : () => _run(() => widget.api.interview(_s(s['id']), skip: true), clearAnswer: true),
            child: const Text('Let VIYO decide'),
          ),
          TextButton(
            onPressed: _busy ? null : () => _run(() => widget.api.interview(_s(s['id']), skip: true, finish: true)),
            child: const Text('Enough questions: plan it'),
          ),
        ]),
      ] else if (iv['ready'] == true) ...[
        const Text(
            'VIYO has what it needs. Anything you didn\'t decide will be listed as VIYO\'s choice for you to check.',
            style: TextStyle(fontSize: 13)),
        const SizedBox(height: 8),
        _outlineButton(s, outlinePrice),
      ] else
        FilledButton(
          onPressed: _busy ? null : () => _run(() => widget.api.interview(_s(s['id']))),
          child: Text('Ask me the first question · ~${creditsLabel(price)}'),
        ),
    ];
  }

  Widget _outlineButton(Map<String, dynamic> s, int price, {String label = 'Plan the whole novel'}) =>
      FilledButton.icon(
        onPressed: _busy ? null : () => _run(() => widget.api.outline(_s(s['id']), _note.text.trim())),
        icon: const Icon(Icons.account_tree_outlined, size: 18),
        label: Text('$label · up to ${creditsLabel(price)}'),
      );

  List<Widget> _outline(Map<String, dynamic> s) {
    final o = _m(s['outline']);
    final approved = s['stage'] == 'outline_approved';
    final problems = _l(s['problems']).map(_s).toList();
    final blocking = _l(s['blocking']).map(_s).toSet();
    final price = (_m(s['prices'])['outline'] as num?)?.toInt() ?? 0;
    const head = TextStyle(fontWeight: FontWeight.w700, fontSize: 13);
    return [
      Text(_s(o['title']), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
      if (_s(o['logline']).isNotEmpty) Text(_s(o['logline']), style: const TextStyle(fontStyle: FontStyle.italic)),
      const SizedBox(height: 6),
      Text(_s(o['premise']), style: const TextStyle(fontSize: 13)),
      if (_l(o['assumptions']).isNotEmpty) ...[
        const SizedBox(height: 10),
        Text('VIYO chose these for you (change them with a note)', style: head.copyWith(color: AppColors.coin)),
        for (final a in _l(o['assumptions'])) Text('• ${_s(a)}', style: const TextStyle(fontSize: 13)),
      ],
      if (problems.isNotEmpty) ...[
        const SizedBox(height: 10),
        const Text('The plan check found', style: head),
        for (final p in problems)
          Text('• $p', style: TextStyle(fontSize: 12, color: blocking.contains(p) ? AppColors.danger : AppColors.coin)),
      ],
      const SizedBox(height: 10),
      const Text('Characters', style: head),
      for (final c in _l(o['characters']).map(_m))
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
              '${_s(c['name'])} · ${_s(c['role'])}'
              '${_s(c['want']).isNotEmpty ? ' — wants ${_s(c['want'])}' : ''}'
              '${_s(c['flaw']).isNotEmpty ? '; flaw: ${_s(c['flaw'])}' : ''}',
              style: const TextStyle(fontSize: 13)),
        ),
      if (_l(o['secrets']).isNotEmpty) ...[
        const SizedBox(height: 10),
        const Text('Secrets', style: head),
        for (final x in _l(o['secrets']).map(_m))
          Text(
              '• ${_s(x['name'])}'
              '${(x['revealed_in_chapter'] as num? ?? 0) > 0 ? ' (comes out in chapter ${x['revealed_in_chapter']})' : ' (stays hidden)'}',
              style: const TextStyle(fontSize: 13)),
      ],
      const SizedBox(height: 10),
      const Text('Chapters', style: head),
      for (final c in _l(o['chapters']).map(_m))
        ExpansionTile(
          dense: true,
          tilePadding: EdgeInsets.zero,
          title: Text('${_s(c['number'])}. ${_s(c['title'])}', style: const TextStyle(fontSize: 13)),
          childrenPadding: const EdgeInsets.only(bottom: 8),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_s(c['summary']), style: const TextStyle(fontSize: 13)),
            for (final b in _l(c['beats'])) Text('– ${_s(b)}', style: const TextStyle(fontSize: 12)),
          ],
        ),
      if (_s(_m(o['ending'])['description']).isNotEmpty) ...[
        const SizedBox(height: 6),
        Text('Ending (${_s(_m(o['ending'])['kind'])})', style: head),
        Text(_s(_m(o['ending'])['description']), style: const TextStyle(fontSize: 13)),
      ],
      const SizedBox(height: 12),
      if (approved) ...[
        const Text('Approved. Its characters, places, secrets and planned threads are in the story memory.',
            style: TextStyle(color: AppColors.success, fontSize: 13)),
        if (_memory != null)
          Text(
              'Added: ${_memory!['entities']} characters, places and secrets; ${_memory!['facts']} facts; '
              '${_memory!['threads']} threads.',
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        NovelChaptersSection(storyId: _s(s['id']), api: widget.chaptersApi),
      ] else ...[
        TextField(
          controller: _note,
          minLines: 1,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'What should change? (optional, for a new version)'),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.icon(
            onPressed: _busy || blocking.isNotEmpty
                ? null
                : () => _run(() => widget.api.approve(_s(s['id']), (s['outline_version'] as num).toInt())),
            icon: const Icon(Icons.check, size: 18),
            label: const Text('Approve this plan'),
          ),
          _outlineButton(s, price, label: 'New version'),
        ]),
      ],
    ];
  }
}
