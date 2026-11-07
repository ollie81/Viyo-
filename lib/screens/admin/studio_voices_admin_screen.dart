import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/creator_studio_service.dart';
import '../../theme/app_theme.dart';
import '../studio/studio_widgets.dart';

/// Internal voice gallery: listen to each voice and record which age groups
/// it really suits. Viyo's automatic casting only gives a child, teenager or
/// older character a voice that has been checked here. Creators never see
/// this screen. The admin key is kept in memory only.
class StudioVoicesAdminScreen extends StatefulWidget {
  const StudioVoicesAdminScreen({super.key});
  @override
  State<StudioVoicesAdminScreen> createState() => _StudioVoicesAdminScreenState();
}

const _ageNames = {
  'infant': 'Baby',
  'young_child': 'Young child (2-7)',
  'older_child': 'Child (8-11)',
  'young_teen': 'Young teen (12-14)',
  'older_teen': 'Teen (15-17)',
  'young_adult': 'Young adult',
  'middle_aged': 'Adult',
  'elderly': 'Older adult (60+)',
};

class _StudioVoicesAdminScreenState extends State<StudioVoicesAdminScreen> {
  final _key = TextEditingController();
  final _player = AudioPlayer();
  List<Map<String, dynamic>> _voices = [];
  int _waiting = 0;
  List<dynamic> _waitingList = [];
  bool _loading = false;
  String? _error;
  String? _playing;
  String? _liveId;
  Map<String, dynamic>? _live;
  Timer? _livePoll;

  @override
  void initState() {
    super.initState();
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playing = null);
    });
  }

  @override
  void dispose() {
    _key.dispose();
    _player.dispose();
    _livePoll?.cancel();
    super.dispose();
  }

  Future<void> _startLive() async {
    if (_key.text.trim().isEmpty) {
      setState(() => _error = 'Enter the admin key.');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: StudioColors.panel,
        title: const Text('Run the live test?'),
        content: const Text('Makes one tiny production with the real AI services: script, characters, voices, '
            'Omni video and sync.so lip sync. Expected about \$2.35, never more than \$5, on Viyo\'s Google and '
            'sync.so accounts. No creator data is touched.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Run it')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final id = await CreatorStudioService.adminStartLiveCheck(_key.text.trim());
      setState(() {
        _liveId = id;
        _live = null;
      });
      _pollLive();
    } on StudioException catch (e) {
      if (mounted) showStudioError(context, e.message);
    }
  }

  void _pollLive() {
    _livePoll?.cancel();
    _livePoll = Timer.periodic(const Duration(seconds: 5), (t) async {
      final id = _liveId;
      if (id == null) return t.cancel();
      try {
        final r = await CreatorStudioService.liveCheckReport(id);
        if (!mounted) return t.cancel();
        setState(() => _live = r);
        if (r['status'] != 'running') t.cancel();
      } catch (_) {}
    });
  }

  String _mark(Object? status) => switch (status) { 'ok' => 'OK', 'failed' => 'FAILED', 'skipped' => 'skipped', _ => '...' };

  Widget _liveCard() {
    final link = CreatorStudioService.liveCheckLink(_liveId!);
    final steps = ((_live?['steps'] as List?) ?? []).cast<Map>();
    final spent = ((_live?['spent_usd'] ?? 0) as num).toStringAsFixed(2);
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: studioPanel(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Live test: ${_live?['status'] ?? 'starting'} · spent \$$spent',
            style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        for (final s in steps)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Text(
              '${_mark(s['status'])}  ${s['step']}'
              '${s['cost_usd'] != null ? ' · \$${(s['cost_usd'] as num).toStringAsFixed(3)}' : ''}'
              '${s['error'] != null ? ' · ${s['error']}' : ''}',
              style: TextStyle(fontSize: 12.5, color: s['status'] == 'failed' ? AppColors.danger : AppColors.textSecondary),
            ),
          ),
        const SizedBox(height: 8),
        const Text('Results link (send it to Claude):', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
        SelectableText(link, style: const TextStyle(fontSize: 12)),
        TextButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: link));
            if (mounted) showStudioError(context, 'Link copied.');
          },
          icon: const Icon(Icons.copy, size: 16),
          label: const Text('Copy link'),
        ),
      ]),
    );
  }

  Future<void> _load() async {
    if (_key.text.trim().isEmpty) {
      setState(() => _error = 'Enter the admin key.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final j = await CreatorStudioService.adminVoices(_key.text.trim());
      setState(() {
        _voices = ((j['voices'] as List?) ?? []).map((v) => Map<String, dynamic>.from(v)).toList();
        _waiting = (j['waiting_count'] as num?)?.toInt() ?? 0;
        _waitingList = (j['characters_waiting'] as List?) ?? [];
      });
    } on StudioException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save(Map<String, dynamic> v, Map<String, dynamic> fields) async {
    try {
      await CreatorStudioService.adminUpdateVoice(_key.text.trim(), v['voice_id'], {...fields, 'checked_by': 'admin'});
      await _load();
    } on StudioException catch (e) {
      if (mounted) showStudioError(context, e.message);
    }
  }

  Future<void> _toggleAge(Map<String, dynamic> v, String age) async {
    final ages = List<String>.from(v['age_categories'] ?? []);
    final adding = !ages.contains(age);
    if (adding && const {'infant', 'young_child', 'older_child', 'young_teen', 'older_teen', 'elderly'}.contains(age)) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: StudioColors.panel,
          title: Text('${v['voice_id']} for ${_ageNames[age]}?'),
          content: const Text('Only confirm this after listening to the sample. Viyo will then cast this voice '
              'automatically for characters of that age.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('I listened, it suits')),
          ],
        ),
      );
      if (ok != true) return;
    }
    adding ? ages.add(age) : ages.remove(age);
    await _save(v, {'age_categories': ages});
  }

  Future<void> _play(Map<String, dynamic> v) async {
    final url = v['sample_url'] as String?;
    if (url == null) return;
    if (_playing == v['voice_id']) {
      await _player.stop();
      setState(() => _playing = null);
      return;
    }
    setState(() => _playing = v['voice_id']);
    try {
      await _player.stop();
      await _player.play(UrlSource(url));
    } catch (_) {
      if (mounted) setState(() => _playing = null);
    }
  }

  Future<void> _makeSamples() async {
    try {
      final dry = await CreatorStudioService.adminMakeSamples(_key.text.trim());
      final todo = (dry['would_make'] as List?) ?? [];
      if (!mounted) return;
      if (todo.isEmpty) {
        showStudioError(context, 'Every voice already has a sample.');
        return;
      }
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: StudioColors.panel,
          title: const Text('Make voice samples?'),
          content: Text('${todo.length} samples with the real voice model. Estimated cost: '
              '\$${(dry['estimated_cost_usd'] as num).toStringAsFixed(4)} on Viyo\'s Google bill. Made once and kept.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Make them')),
          ],
        ),
      );
      if (ok != true) return;
      setState(() => _loading = true);
      final done = await CreatorStudioService.adminMakeSamples(_key.text.trim(), confirmSpend: true);
      final failed = (done['failed'] as List?) ?? [];
      if (mounted && failed.isNotEmpty) {
        showStudioError(context, '${failed.length} failed: ${failed.first['error']}');
      }
      await _load();
    } on StudioException catch (e) {
      if (mounted) showStudioError(context, e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(backgroundColor: AppColors.background, title: const Text('Studio voice gallery')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Row(children: [
              Expanded(child: TextField(controller: _key, obscureText: true, decoration: studioField('Admin key'))),
              const SizedBox(width: 10),
              FilledButton(onPressed: _loading ? null : _load, child: const Text('Load')),
            ]),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(_error!, style: const TextStyle(color: AppColors.danger)),
              ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _liveId != null && _live?['status'] == 'running' ? null : _startLive,
                icon: const Icon(Icons.science_outlined, size: 18),
                label: const Text('Run live test (max \$5)'),
              ),
            ),
            if (_liveId != null) _liveCard(),
            if (_voices.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                'Automatic casting only uses the age groups ticked here. Tick a child, teen or older group only '
                'after listening to the sample.',
                style: const TextStyle(color: AppColors.textSecondary, height: 1.4),
              ),
              const SizedBox(height: 8),
              Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                OutlinedButton.icon(
                  onPressed: _loading ? null : _makeSamples,
                  icon: const Icon(Icons.graphic_eq, size: 18),
                  label: const Text('Make missing samples'),
                ),
                if (_waiting > 0)
                  Text('$_waiting character${_waiting == 1 ? '' : 's'} waiting for a suitable voice'
                      '${_waitingList.isEmpty ? '' : ' (e.g. ${_waitingList.first['name']}, ${_ageNames[_waitingList.first['age_category']] ?? 'unknown age'})'}',
                      style: const TextStyle(color: AppColors.coin, fontSize: 13)),
              ]),
              const SizedBox(height: 12),
              for (final v in _voices) _voiceCard(v),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _voiceCard(Map<String, dynamic> v) {
    final ages = List<String>.from(v['age_categories'] ?? []);
    final available = v['status'] == 'available';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: studioPanel(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          IconButton(
            tooltip: v['sample_url'] == null ? 'No sample yet' : 'Listen',
            onPressed: v['sample_url'] == null ? null : () => _play(v),
            icon: Icon(_playing == v['voice_id'] ? Icons.stop_circle_outlined : Icons.play_circle_outline),
          ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${v['voice_id']}', style: const TextStyle(fontWeight: FontWeight.w700)),
              Text('${v['descriptor']} · ${v['gender']} · used by ${v['characters']} · checked: ${v['verified_by']}',
                  style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
            ]),
          ),
          const Text('Castable', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          Switch(value: available, onChanged: (on) => _save(v, {'status': on ? 'available' : 'unavailable'})),
        ]),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final age in _ageNames.keys)
            FilterChip(
              visualDensity: VisualDensity.compact,
              label: Text(_ageNames[age]!, style: const TextStyle(fontSize: 12)),
              selected: ages.contains(age),
              onSelected: (_) => _toggleAge(v, age),
            ),
        ]),
        if ((v['notes'] ?? '').toString().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('${v['notes']}', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
          ),
      ]),
    );
  }
}
