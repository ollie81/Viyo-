import 'package:flutter/material.dart';

import '../../services/creator_studio_service.dart';
import '../../theme/app_theme.dart';
import 'studio_widgets.dart';

/// The story world (where and when, researched once and reused by every step)
/// and the larger story (the series planned before episodes). The creator
/// chooses the kind of world, sees which facts are documented and which are
/// invented or uncertain, corrects what's wrong, and approves.
class StudioWorldCard extends StatefulWidget {
  final String projectId;
  final Future<void> Function() reload;
  const StudioWorldCard({super.key, required this.projectId, required this.reload});
  @override
  State<StudioWorldCard> createState() => _StudioWorldCardState();
}

class _StudioWorldCardState extends State<StudioWorldCard> {
  Map<String, dynamic>? _d;
  Map<String, dynamic>? _voices;
  bool _busy = false;
  String _mode = 'grounded';
  final _setting = TextEditingController();
  String _length = 'open';
  final _count = TextEditingController(text: '10');

  static const _modeLabels = {
    'grounded': 'Historical (true to the period)',
    'alternate': 'Alternate history',
    'fictional': 'Fictional world inspired by a culture',
    'modern': 'Modern real place',
  };
  static const _statusColor = {
    'documented': AppColors.success,
    'interpretation': AppColors.primary,
    'invented': AppColors.secondary,
    'uncertain': AppColors.coin,
    'unsourced': AppColors.danger,
  };
  static const _fields = {
    'setting.era': 'Era / period',
    'setting.place': 'Place',
    'material.clothing': 'Clothing',
    'material.architecture': 'Buildings',
    'material.hair_and_adornment': 'Hair and adornment',
    'culture.respect_and_greetings': 'Respect and greetings',
    'culture.beliefs': 'Beliefs',
    'language.naming': 'Names',
    'society.family': 'Family',
    'technology.transport': 'Transport',
    'environment.landscape': 'Landscape',
    'sound.music': 'Music',
    'avoid': 'Something that must never appear',
    'unknown': 'Something that isn\'t known',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _setting.dispose();
    _count.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final d = await CreatorStudioService.world(widget.projectId);
      Map<String, dynamic>? v;
      try {
        v = await CreatorStudioService.voiceBible(widget.projectId);
      } on StudioException {
        v = null;
      }
      if (mounted) {
        setState(() {
          _d = d;
          _voices = v;
        });
      }
    } on StudioException catch (e) {
      if (mounted) showStudioError(context, e.message);
    }
  }

  String _s(Object? v) => (v ?? '').toString().trim();
  String _rid() => DateTime.now().microsecondsSinceEpoch.toString();

  Future<void> _run(Future<void> Function() f) async {
    setState(() => _busy = true);
    try {
      await f();
      await _load();
      await widget.reload();
    } on StudioException catch (e) {
      if (mounted) showStudioError(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String title, String body) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: StudioColors.panel,
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Continue')),
          ],
        ),
      ) ==
      true;

  Future<void> _build() async {
    final prices = Map<String, dynamic>.from((_d?['prices'] as Map?) ?? {});
    final credits = _mode == 'fictional' ? prices['world_fictional'] : prices['world'];
    if (!await _confirm('Build the story world?',
        '${_mode == 'fictional' ? 'Viyo designs the world from its inspiration.' : 'Viyo researches the place and period on the web, then builds the world.'} '
        'It\'s made once and used for the story, characters, pictures, videos and music. About $credits credits; nothing if it fails.')) {
      return;
    }
    await _run(() => CreatorStudioService.buildWorld(widget.projectId, _mode, _setting.text.trim(), _rid()));
  }

  Future<void> _plan() async {
    final credits = ((_d?['prices'] as Map?) ?? {})['saga'];
    if (!await _confirm('Plan the larger story?',
        'Viyo plans the whole series before episodes: storylines, character arcs, secrets, mysteries, turning points and seasons. '
        'About $credits credits; nothing if it fails.')) {
      return;
    }
    await _run(() => CreatorStudioService.planSaga(widget.projectId, _length, int.tryParse(_count.text) ?? 0, _rid()));
  }

  Future<void> _correct() async {
    var field = _fields.keys.first;
    final value = TextEditingController();
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          backgroundColor: StudioColors.panel,
          title: const Text('Correct the world'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String>(
                initialValue: field,
                isExpanded: true,
                dropdownColor: StudioColors.panel,
                decoration: studioField('What'),
                items: [for (final e in _fields.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                onChanged: (v) => set(() => field = v ?? field),
              ),
              const SizedBox(height: 8),
              TextField(controller: value, maxLines: 3, decoration: studioField('What it should be')),
              const SizedBox(height: 8),
              TextField(controller: note, decoration: studioField('Why (optional)', hint: 'e.g. how my family describes it')),
              const SizedBox(height: 6),
              const Text('Your correction overrides what the AI assumed, everywhere: story, characters, pictures and videos.',
                  style: TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save correction')),
          ],
        ),
      ),
    );
    if (ok == true && value.text.trim().isNotEmpty) {
      await _run(() => CreatorStudioService.correctWorld(widget.projectId, field, value.text.trim(), note.text.trim()));
    }
  }

  Widget _row(String label, String value) => value.isEmpty
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text.rich(TextSpan(children: [
            TextSpan(text: '$label: ', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
            TextSpan(text: value, style: const TextStyle(fontSize: 12.5, height: 1.35)),
          ])),
        );

  String _sec(Map w, String sec, List<String> keys) {
    final m = Map<String, dynamic>.from((w[sec] as Map?) ?? {});
    return keys.where((k) => m[k] != null && _s(m[k]).isNotEmpty).map((k) {
      final v = m[k];
      return v is List ? v.map((e) => e is Map ? '${e['word'] ?? ''} (${e['meaning'] ?? ''})' : '$e').join(', ') : '$v';
    }).join(' · ');
  }

  Widget _worldView(Map<String, dynamic> w) {
    final st = Map<String, dynamic>.from((w['setting'] as Map?) ?? {});
    final facts = ((w['facts'] as List?) ?? []).whereType<Map>().toList();
    final check = Map<String, dynamic>.from((_d?['check'] as Map?) ?? {});
    final problems = ((check['problems'] as List?) ?? []).whereType<Map>().toList();
    final sources = ((w['sources'] as List?) ?? []).whereType<Map>().toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('${_s(st['place'])}${_s(st['country']).isNotEmpty ? ', ${_s(st['country'])}' : ''} · ${_s(st['era'])}',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
      Text(
          '${_modeLabels[w['mode']] ?? w['mode']} · ${w['researched'] == true ? 'researched with web search (${sources.length} sources)' : 'not researched with web search'}'
          '${_d?['inherited'] == true ? ' · from earlier episodes' : ''}',
          style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
      const SizedBox(height: 6),
      Text(_s(st['summary']), style: const TextStyle(fontSize: 12.5, height: 1.4)),
      const SizedBox(height: 8),
      _row('Society', _sec(w, 'society', ['power', 'social_structure', 'family', 'wealth_and_status'])),
      _row('Manners', _sec(w, 'culture', ['respect_and_greetings', 'how_emotion_is_shown', 'traditions', 'beliefs'])),
      _row('Names', _sec(w, 'language', ['spoken', 'naming', 'example_names', 'forms_of_address'])),
      _row('Clothing', _sec(w, 'material', ['clothing', 'clothing_by_status', 'hair_and_adornment'])),
      _row('Buildings and objects', _sec(w, 'material', ['architecture', 'interiors', 'objects'])),
      _row('Technology', _sec(w, 'technology', ['available', 'transport'])),
      _row('Never shown', [..._list(w['technology'], 'not_available'), ...((w['avoid'] as List?) ?? []).map((e) => '$e')].join(', ')),
      _row('Landscape and light', _sec(w, 'environment', ['landscape', 'climate', 'light'])),
      _row('Sound and music', _sec(w, 'sound', ['ambience', 'music', 'instruments'])),
      if (facts.isNotEmpty) ...[
        const SizedBox(height: 4),
        const Text('Facts the story relies on', style: TextStyle(fontSize: 11.5, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
        for (final f in facts)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                margin: const EdgeInsets.only(right: 6, top: 1),
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                    border: Border.all(color: _statusColor[f['status']] ?? AppColors.textMuted), borderRadius: BorderRadius.circular(4)),
                child: Text(f['status'] == 'unsourced' ? 'not verified' : _s(f['status']),
                    style: TextStyle(fontSize: 10.5, color: _statusColor[f['status']] ?? AppColors.textMuted)),
              ),
              Expanded(
                child: Text(
                    '${_s(f['claim'])}${f['source'] is Map ? ' (${_s((f['source'] as Map)['title'])})' : ''}${_s(f['note']).isNotEmpty ? ' – ${_s(f['note'])}' : ''}',
                    style: const TextStyle(fontSize: 12, height: 1.35)),
              ),
            ]),
          ),
      ],
      _row('Not known or disputed', ((w['unknown'] as List?) ?? []).map((e) => '$e').join('; ')),
      for (final c in ((w['corrections'] as List?) ?? []).whereType<Map>())
        Text('You corrected ${_fields[c['field']] ?? c['field']}: ${_s(c['value'])}',
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      for (final p in problems) Text('⚠ ${_s(p['problem'])}', style: const TextStyle(fontSize: 12, color: AppColors.coin)),
      Wrap(spacing: 6, children: [
        if (_d?['inherited'] != true)
          FilterChip(
            label: Text(w['approved'] == true ? 'World approved' : 'Approve world', style: const TextStyle(fontSize: 12)),
            selected: w['approved'] == true,
            onSelected: _busy ? null : (v) => _run(() => CreatorStudioService.approveWorld(widget.projectId, v)),
          ),
        TextButton.icon(onPressed: _busy ? null : _correct, icon: const Icon(Icons.edit_note, size: 16), label: const Text('Correct something')),
        TextButton.icon(onPressed: _busy ? null : _build, icon: const Icon(Icons.refresh, size: 16), label: const Text('Rebuild')),
      ]),
    ]);
  }

  static const _voiceFields = {
    'identity': 'The voice in one sentence',
    'pitch': 'Pitch',
    'texture': 'Texture',
    'accent': 'Accent',
    'speed': 'Pace',
    'rhythm': 'Rhythm and pauses',
    'vocal_age': 'Sounds like (age)',
    'emotional_range': 'How they sound when emotional',
  };

  Future<void> _editVoice(String name, Map<String, dynamic> v) async {
    var field = 'identity';
    final value = TextEditingController(text: _s(v['identity']));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          backgroundColor: StudioColors.panel,
          title: Text('$name\'s voice'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              initialValue: field,
              isExpanded: true,
              dropdownColor: StudioColors.panel,
              decoration: studioField('What to change'),
              items: [for (final e in _voiceFields.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
              onChanged: (f) => set(() {
                field = f ?? field;
                value.text = _s(v[field]);
              }),
            ),
            const SizedBox(height: 8),
            TextField(controller: value, maxLines: 3, decoration: studioField('New direction')),
            const SizedBox(height: 6),
            const Text('Used for every clip from now on. Clips already made keep their voice until remade.',
                style: TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (ok == true && value.text.trim().isNotEmpty) {
      await _run(() => CreatorStudioService.editVoice(widget.projectId, name, {field: value.text.trim()}));
    }
  }

  Widget _voicesView() {
    final voices = Map<String, dynamic>.from((_voices?['voices'] as Map?) ?? {});
    if (voices.isEmpty) {
      return const Text('Voices are cast from the story when the script is broken into scenes.',
          style: TextStyle(fontSize: 12, color: AppColors.textMuted));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final v in voices.values.whereType<Map>())
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Text.rich(TextSpan(children: [
                TextSpan(text: '${v['character']}: ', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
                TextSpan(
                    text: [_s(v['identity']), if (_s(v['accent']).isNotEmpty) '${_s(v['accent'])} accent', if (_s(v['speed']).isNotEmpty) _s(v['speed'])]
                        .join(' · '),
                    style: const TextStyle(fontSize: 12.5, height: 1.35)),
                if (v['fallback'] == true)
                  const TextSpan(text: ' (basic, not directed yet)', style: TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
              ])),
            ),
            IconButton(
                tooltip: 'Change voice',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.edit_outlined, size: 16),
                onPressed: _busy ? null : () => _editVoice('${v['character']}', Map<String, dynamic>.from(v))),
          ]),
        ),
      const Text('No video model takes a fixed voice, so the same direction is sent every time; voices can still drift '
          'a little between clips. Saved voices never change.', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
    ]);
  }

  List<String> _list(Object? m, String key) => ((m is Map ? m[key] : null) as List? ?? []).map((e) => '$e').toList();

  Widget _sagaView(Map<String, dynamic> s) {
    final chars = ((s['characters'] as List?) ?? []).whereType<Map>().toList();
    final probs = ((_d?['saga_problems'] as List?) ?? []).map((e) => '$e').toList();
    final revealed = ((s['revealed'] as List?) ?? []).map((e) => '$e').toSet();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(_s(s['premise']), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
      _row('Main storyline', _s(s['main_storyline'])),
      for (final se in ((s['seasons'] as List?) ?? []).whereType<Map>())
        _row('Season ${se['number']}', '${_s(se['arc'])} – ends with ${_s(se['ends_with'])}'),
      for (final tp in ((s['turning_points'] as List?) ?? []).whereType<Map>()) _row('Episode ${tp['episode']}', _s(tp['what'])),
      for (final c in chars)
        _row(_s(c['name']),
            'wants ${_s(c['wants'])}; afraid of losing ${_s(c['fears_losing'])}; hides ${_s(c['hides'])}; ${_s(c['inner_conflict'])}; arc: ${_s(c['arc'])}'),
      for (final sc in ((s['secrets'] as List?) ?? []).whereType<Map>())
        _row('Secret (episode ${sc['reveal_episode']}${revealed.contains(sc['secret']) ? ', revealed' : ''})', _s(sc['secret'])),
      _row('Future seasons', ((s['future_seasons'] as List?) ?? []).map((e) => '$e').join('; ')),
      for (final p in probs) Text('⚠ $p', style: const TextStyle(fontSize: 12, color: AppColors.coin)),
      Wrap(spacing: 6, children: [
        FilterChip(
          label: Text(s['approved'] == true ? 'Series plan approved' : 'Approve series plan', style: const TextStyle(fontSize: 12)),
          selected: s['approved'] == true,
          onSelected: _busy ? null : (v) => _run(() => CreatorStudioService.approveSaga(widget.projectId, v)),
        ),
        TextButton.icon(onPressed: _busy ? null : _plan, icon: const Icon(Icons.refresh, size: 16), label: const Text('Plan again')),
      ]),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    if (d == null) return const SizedBox.shrink();
    final world = d['world'] is Map ? Map<String, dynamic>.from(d['world'] as Map) : null;
    final saga = d['saga'] is Map ? Map<String, dynamic>.from(d['saga'] as Map) : null;
    return Container(
      decoration: studioPanel(),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: world == null,
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          leading: const Icon(Icons.public, color: AppColors.secondary),
          title: const Text('Story world & series', style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(
              world == null
                  ? 'Where and when your story happens: researched once, used for the story, characters, pictures, videos and music.'
                  : '${_s((world['setting'] as Map?)?['place'])} · ${_s((world['setting'] as Map?)?['era'])}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_busy) const LinearProgressIndicator(minHeight: 2),
            if (world == null) ...[
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final e in _modeLabels.entries)
                  ChoiceChip(
                    label: Text(e.value, style: const TextStyle(fontSize: 12)),
                    selected: _mode == e.key,
                    onSelected: (_) => setState(() => _mode = e.key),
                  ),
              ]),
              const SizedBox(height: 8),
              TextField(
                  controller: _setting,
                  decoration: studioField('Setting', hint: 'e.g. Rwanda around 1500, a royal court in the highlands')),
              const SizedBox(height: 6),
              FilledButton.icon(
                  onPressed: _busy ? null : _build, icon: const Icon(Icons.travel_explore, size: 18), label: const Text('Build the world')),
            ] else
              _worldView(world),
            const Divider(height: 24),
            const Text('Character voices', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            const SizedBox(height: 4),
            _voicesView(),
            const Divider(height: 24),
            const Text('Larger story', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            const SizedBox(height: 4),
            if (saga == null) ...[
              Wrap(spacing: 6, children: [
                for (final e in const {'episodes': 'A set number of episodes', 'seasons': 'Seasons', 'open': 'Open-ended'}.entries)
                  ChoiceChip(
                    label: Text(e.value, style: const TextStyle(fontSize: 12)),
                    selected: _length == e.key,
                    onSelected: (_) => setState(() => _length = e.key),
                  ),
              ]),
              if (_length != 'open')
                SizedBox(
                  width: 160,
                  child: TextField(
                      controller: _count,
                      keyboardType: TextInputType.number,
                      decoration: studioField(_length == 'episodes' ? 'Episodes' : 'Seasons')),
                ),
              const SizedBox(height: 6),
              OutlinedButton.icon(
                  onPressed: _busy ? null : _plan, icon: const Icon(Icons.account_tree_outlined, size: 18), label: const Text('Plan the series')),
            ] else
              _sagaView(saga),
          ],
        ),
      ),
    );
  }
}
