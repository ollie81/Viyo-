import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../services/creator_studio_service.dart';
import '../../services/file_saver_io.dart' if (dart.library.html) '../../services/file_saver_web.dart' as saver;
import '../../theme/app_theme.dart';
import 'studio_elements_section.dart';
import 'studio_identity_section.dart';
import 'studio_production_panel.dart';
import 'studio_widgets.dart';

/// One production's workspace: Story -> Cast -> Scenes -> Export, with a
/// live activity panel. Three columns on a desktop browser, tabs on a phone.
class StudioProjectScreen extends StatefulWidget {
  final String projectId;
  const StudioProjectScreen({super.key, required this.projectId});
  @override
  State<StudioProjectScreen> createState() => _StudioProjectScreenState();
}

class _StudioProjectScreenState extends State<StudioProjectScreen> with SingleTickerProviderStateMixin {
  StudioProjectDetail? _d;
  List<StudioVoice> _voices = [];
  List<StudioEffect> _effects = [];
  bool _lipsync = false;
  String? _error;
  int _section = 0;
  Timer? _poll;
  late final TabController _tabs = TabController(length: 4, vsync: this)
    ..addListener(() {
      if (!_tabs.indexIsChanging) setState(() => _section = _tabs.index);
    });

  /// Moves to a section and keeps the phone tab bar in step with it.
  void _goTo(int i) {
    setState(() => _section = i);
    if (_tabs.index != i) _tabs.animateTo(i);
  }

  static const _sections = [
    (Icons.edit_note, 'Story'),
    (Icons.groups_outlined, 'Cast'),
    (Icons.view_carousel_outlined, 'Scenes'),
    (Icons.movie_outlined, 'Export'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
    CreatorStudioService.account().then((a) {
      if (mounted) {
        setState(() {
          if (_voices.isEmpty) _voices = a.voices;
          _effects = a.effects;
          _lipsync = a.lipsyncAvailable;
        });
      }
    }).catchError((_) {});
    CreatorStudioService.voices().then((v) {
      if (mounted && v.isNotEmpty) setState(() => _voices = v);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _poll?.cancel();
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final d = await CreatorStudioService.project(widget.projectId);
      if (!mounted) return;
      setState(() {
        _d = d;
        _error = null;
      });
      _schedulePoll();
    } on StudioException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  void _schedulePoll() {
    _poll?.cancel();
    if (_d?.producing ?? false) {
      // A one-click production moves between steps on its own: keep refreshing.
      _poll = Timer(const Duration(seconds: 5), () async {
        if (mounted) await _load();
      });
      return;
    }
    if (!(_d?.jobs.any((j) => j.active) ?? false)) return;
    _poll = Timer(const Duration(seconds: 3), () async {
      try {
        final before = _d?.jobs.where((j) => j.active).map((j) => j.id).toSet() ?? {};
        final (jobs, _) = await CreatorStudioService.jobs(widget.projectId);
        final stillActive = jobs.where((j) => j.active).map((j) => j.id).toSet();
        if (!mounted) return;
        if (before.difference(stillActive).isNotEmpty) {
          final failed = jobs.where((j) => before.contains(j.id) && j.status == 'failed').toList();
          if (failed.isNotEmpty) showStudioError(context, failed.first.error ?? 'Something failed. Your credits were returned.');
          await _load();
        } else {
          _schedulePoll();
        }
      } catch (_) {
        _schedulePoll();
      }
    });
  }

  void _started(StudioBalance _) {
    showStudioInfo(context, 'Started. You can keep working; this updates by itself.');
    _load();
  }

  Future<void> _needCredits() async {
    await showCreditsSheet(context);
    _load();
  }

  Future<bool> _run(String kind,
          {List<String> targets = const [], String? warning, Map<String, dynamic> extra = const {}, String? title}) =>
      confirmAndRun(
        context,
        projectId: widget.projectId,
        kind: kind,
        targets: targets,
        extraWarning: warning,
        extra: extra,
        title: title,
        onStarted: _started,
        onNeedCredits: _needCredits,
      );

  bool _busy(String kind, {String? sceneId, String? characterId}) => (_d?.jobs ?? []).any((j) =>
      j.active && j.kind == kind && (sceneId == null || j.sceneId == sceneId) && (characterId == null || j.characterId == characterId));

  Future<void> _nextEpisode() async {
    final d = _d;
    if (d == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: StudioColors.panel,
        title: const Text('Make the next episode?'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Text(
            'A new production with the same settings and the same ${d.characters.length} characters. '
            'Each character keeps their voice, delivery note and portrait. This doesn\'t use any credits.',
            style: const TextStyle(height: 1.4),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Make next episode')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final id = await CreatorStudioService.nextEpisode(d.project.id);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => StudioProjectScreen(projectId: id)));
    } on StudioException catch (e) {
      if (mounted) showStudioError(context, e.message);
    }
  }

  Future<void> _archive() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: StudioColors.panel,
        title: const Text('Archive this production?'),
        content: const Text('It disappears from your list. Its files and renders are kept.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Archive')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await CreatorStudioService.archiveProject(widget.projectId);
      if (mounted) Navigator.pop(context);
    } on StudioException catch (e) {
      if (mounted) showStudioError(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    final width = MediaQuery.of(context).size.width;
    final wide = width >= 1150, mid = width >= 760;
    final active = d?.jobs.where((j) => j.active).length ?? 0;
    return Scaffold(
      backgroundColor: AppColors.background,
      endDrawer: wide || d == null ? null : Drawer(backgroundColor: AppColors.background, width: 340, child: SafeArea(child: _ActivityPanel(d, onCancel: _cancel))),
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: Text(d?.project.title ?? 'Production', style: const TextStyle(fontWeight: FontWeight.w700)),
        bottom: mid || d == null
            ? null
            : TabBar(controller: _tabs, isScrollable: false, tabs: [for (final (_, label) in _sections) Tab(text: label)]),
        actions: [
          if (d != null) Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: Center(child: CreditPill(balance: d.balance, onTap: _needCredits))),
          if (d != null && !wide)
            Builder(
              builder: (ctx) => IconButton(
                tooltip: 'Activity',
                onPressed: () => Scaffold.of(ctx).openEndDrawer(),
                icon: Badge(isLabelVisible: active > 0, label: Text('$active'), child: const Icon(Icons.pending_actions_outlined)),
              ),
            ),
          PopupMenuButton<String>(
            onSelected: (v) => switch (v) { 'archive' => _archive(), 'next' => _nextEpisode(), _ => _load() },
            itemBuilder: (_) => [
              if (d != null) const PopupMenuItem(value: 'next', child: Text('Make next episode')),
              const PopupMenuItem(value: 'refresh', child: Text('Refresh')),
              const PopupMenuItem(value: 'archive', child: Text('Archive production')),
            ],
          ),
        ],
      ),
      body: d == null
          ? Center(
              child: _error == null
                  ? const CircularProgressIndicator()
                  : Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(_error!, style: const TextStyle(color: AppColors.textSecondary)),
                      const SizedBox(height: 12),
                      OutlinedButton(onPressed: _load, child: const Text('Try again')),
                    ]))
          : Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (mid)
                NavigationRail(
                  backgroundColor: StudioColors.panel,
                  selectedIndex: _section,
                  labelType: NavigationRailLabelType.all,
                  indicatorColor: AppColors.primary.withValues(alpha: 0.15),
                  selectedIconTheme: const IconThemeData(color: AppColors.primary),
                  onDestinationSelected: _goTo,
                  destinations: [
                    for (final (icon, label) in _sections) NavigationRailDestination(icon: Icon(icon), label: Text(label)),
                  ],
                ),
              Expanded(child: _content(d, mid)),
              if (wide)
                Container(
                  width: 330,
                  decoration: const BoxDecoration(border: Border(left: BorderSide(color: StudioColors.panelBorder))),
                  child: _ActivityPanel(d, onCancel: _cancel),
                ),
            ]),
    );
  }

  Future<void> _cancel(StudioJob j) async {
    try {
      await CreatorStudioService.cancelJob(j.id);
      if (mounted) showStudioInfo(context, 'Cancelled. Credits returned.');
      _load();
    } on StudioException catch (e) {
      if (mounted) showStudioError(context, e.message);
    }
  }

  Widget _content(StudioProjectDetail d, bool mid) {
    final section = switch (_section) {
      0 => _StoryPanel(d, run: _run, busy: _busy, reload: _load, goTo: _goTo),
      1 => _CastPanel(d, voices: _voices, run: _run, busy: _busy, reload: _load),
      2 => _ScenesPanel(d, effects: _effects, lipsync: _lipsync, run: _run, busy: _busy, reload: _load),
      _ => _ExportPanel(d, run: _run, busy: _busy, reload: _load, onNeedCredits: _needCredits),
    };
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 980), child: section),
    );
  }
}

typedef _Run = Future<bool> Function(String kind,
    {List<String> targets, String? warning, Map<String, dynamic> extra, String? title});
typedef _Busy = bool Function(String kind, {String? sceneId, String? characterId});

Widget _sectionHeader(String title, String subtitle, {List<Widget> actions = const []}) => Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, spacing: 12, runSpacing: 10, children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(subtitle, style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
        ]),
        Wrap(spacing: 8, runSpacing: 8, children: actions),
      ]),
    );

Widget _busyChip(String text) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
        const SizedBox(width: 8),
        Text(text, style: const TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w600)),
      ]),
    );

ButtonStyle get _primaryBtn => FilledButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.black);

// ================================================================ Story

class _StoryPanel extends StatefulWidget {
  final StudioProjectDetail d;
  final _Run run;
  final _Busy busy;
  final Future<void> Function() reload;
  final void Function(int) goTo;
  const _StoryPanel(this.d, {required this.run, required this.busy, required this.reload, required this.goTo});
  @override
  State<_StoryPanel> createState() => _StoryPanelState();
}

class _StoryPanelState extends State<_StoryPanel> {
  late final _idea = TextEditingController(text: widget.d.project.logline);
  late final _script = TextEditingController(text: widget.d.project.script);
  late final _style = TextEditingController(text: widget.d.project.visualStyle);
  bool _saving = false;
  bool _assistantLoading = true;
  bool _assistantWorking = false;
  bool _approving = false;
  Map<String, dynamic>? _assistant;
  String? _assistantError;

  @override
  void initState() {
    super.initState();
    _loadAssistant();
  }

  @override
  void didUpdateWidget(covariant _StoryPanel old) {
    super.didUpdateWidget(old);
    // A finished AI script replaces the editor text unless the creator is mid-edit.
    if (old.d.project.script != widget.d.project.script && _script.text == old.d.project.script) {
      _script.text = widget.d.project.script;
      _loadAssistant();
    } else if (old.d.project.storyBible != widget.d.project.storyBible) {
      _loadAssistant();
    }
  }

  @override
  void dispose() {
    _idea.dispose();
    _script.dispose();
    _style.dispose();
    super.dispose();
  }

  bool get _dirty =>
      _idea.text != widget.d.project.logline || _script.text != widget.d.project.script || _style.text != widget.d.project.visualStyle;

  Future<void> _loadAssistant() async {
    setState(() {
      _assistantLoading = true;
      _assistantError = null;
    });
    try {
      final state = await CreatorStudioService.assistantState(widget.d.project.id);
      if (!mounted) return;
      setState(() => _assistant = state);
    } on StudioException catch (e) {
      if (!mounted) return;
      setState(() => _assistantError = e.message);
    } finally {
      if (mounted) setState(() => _assistantLoading = false);
    }
  }

  Future<bool> _save() async {
    if (!_dirty) return true;
    setState(() => _saving = true);
    try {
      await CreatorStudioService.updateProject(widget.d.project.id,
          {'logline': _idea.text, 'script': _script.text, 'visual_style': _style.text});
      await widget.reload();
      return true;
    } on StudioException catch (e) {
      if (mounted) showStudioError(context, e.message);
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _developStory() async {
    if (_idea.text.trim().isEmpty) {
      showStudioError(context, 'Write a short idea first so Viyo knows what story to develop.');
      return;
    }
    if (!await _save() || !mounted) return;
    setState(() => _assistantWorking = true);
    try {
      final estimate = await CreatorStudioService.estimate(widget.d.project.id, 'script');
      if (estimate.readyCount == 0) {
        showStudioError(context, estimate.blockedReasons.isNotEmpty ? estimate.blockedReasons.first : 'This story cannot be generated yet.');
        return;
      }
      if (estimate.totalCredits > estimate.balance.available) {
        final shortBy = estimate.totalCredits - estimate.balance.available;
        final getCredits = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: StudioColors.panel,
            title: const Text('More Studio credits needed'),
            content: Text('This story costs ${creditsLabel(estimate.totalCredits)}. '
                'Your available balance is ${creditsLabel(estimate.balance.available)}. '
                'You need ${creditsLabel(shortBy)} more.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Not now')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('View credits')),
            ],
          ),
        );
        if (getCredits == true && mounted) await showCreditsSheet(context);
        return;
      }
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: StudioColors.panel,
          title: const Text('Develop this story?'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Viyo will develop your idea into a story plan and screenplay. You can review and edit them before creating scenes.'),
            const SizedBox(height: 14),
            _assistantCostRow('Full price', creditsLabel(estimate.totalCredits), bold: true),
            _assistantCostRow('Available balance', creditsLabel(estimate.balance.available)),
            _assistantCostRow('After this', creditsLabel(estimate.balance.available - estimate.totalCredits)),
            const SizedBox(height: 8),
            const Text('Credits are only charged for successful work. Failed jobs are refunded.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.4)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Start · ${creditsLabel(estimate.totalCredits)}')),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      await CreatorStudioService.assistantGenerate(
        widget.d.project.id,
        requestId: CreatorStudioService.newRequestId(),
        confirmCredits: estimate.totalCredits,
      );
      if (!mounted) return;
      showStudioInfo(context, 'Viyo is developing your story. You can keep working while it runs.');
      await _loadAssistant();
      await widget.reload();
    } on StudioException catch (e) {
      if (mounted) showStudioError(context, e.message);
    } finally {
      if (mounted) setState(() => _assistantWorking = false);
    }
  }

  Future<void> _approveStory() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: StudioColors.panel,
        title: const Text('Approve this story?'),
        content: const Text('This confirms you are happy with the story plan and screenplay. You can then continue to character casting and scene production.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Review more')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Approve story')),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() => _approving = true);
    try {
      if (!await _save()) return;
      await CreatorStudioService.assistantApprove(widget.d.project.id);
      await _loadAssistant();
      await widget.reload();
      if (mounted) showStudioInfo(context, 'Story approved. You can continue to casting and scenes.');
    } on StudioException catch (e) {
      if (mounted) showStudioError(context, e.message);
    } finally {
      if (mounted) setState(() => _approving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.d.project;
    final writing = widget.busy('script'), splitting = widget.busy('breakdown');
    final sceneCount = widget.d.scenes.length;
    final assistantStatus = _assistant?['story_status'] as String? ?? 'not_started';
    final scriptJob = _assistant?['script_job'] as Map?;
    final assistantJobActive = scriptJob?['status'] == 'queued' || scriptJob?['status'] == 'running';
    final hasStory = p.script.trim().isNotEmpty && p.storyBible != null;
    final approved = assistantStatus == 'approved';
    final approvalRequired = p.storyBible != null && !approved;
    return ListView(padding: const EdgeInsets.fromLTRB(20, 20, 20, 40), children: [
      _sectionHeader('Story', '${p.vertical ? 'Vertical 9:16' : 'Landscape 16:9'} · ${p.genre.isEmpty ? 'Drama' : p.genre} · about ${p.targetSeconds} s · ${p.language}',
          actions: [
            if (_dirty)
              OutlinedButton.icon(onPressed: _saving ? null : _save, icon: const Icon(Icons.save_outlined, size: 18), label: const Text('Save')),
          ]),
      Container(
        decoration: studioPanel(border: AppColors.primary.withValues(alpha: 0.35)),
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Icon(Icons.auto_awesome, color: AppColors.primary),
            const SizedBox(width: 8),
            const Expanded(child: Text('Viyo Story Assistant', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
            if (_assistantLoading)
              const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            else if (approved)
              _assistantBadge('Approved', AppColors.success)
            else if (hasStory)
              _assistantBadge('Draft ready', AppColors.coin),
          ]),
          const SizedBox(height: 8),
          const Text('Start with an idea. Viyo develops the story world and screenplay for you. Review everything before moving into character casting and scenes.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.45)),
          const SizedBox(height: 14),
          TextField(controller: _idea, onChanged: (_) => setState(() {}), maxLines: 3, maxLength: 2000,
              decoration: studioField('Your idea', hint: 'Who is it about, what do they want, and what goes wrong?')),
          const SizedBox(height: 6),
          TextField(controller: _style, onChanged: (_) => setState(() {}), decoration: studioField('Visual style', hint: 'Cinematic, realistic, warm lighting…')),
          if (_assistantError != null) ...[
            const SizedBox(height: 10),
            Text(_assistantError!, style: const TextStyle(color: AppColors.danger, fontSize: 12)),
            Align(alignment: Alignment.centerLeft, child: TextButton(onPressed: _loadAssistant, child: const Text('Retry assistant connection'))),
          ],
          const SizedBox(height: 12),
          Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            FilledButton.icon(
              style: _primaryBtn,
              onPressed: _assistantLoading || _assistantWorking || writing || approved || _assistantError != null ? null : _developStory,
              icon: _assistantWorking || assistantJobActive
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.auto_awesome, size: 18),
              label: Text(assistantJobActive ? 'Developing story…' : hasStory ? 'Develop again' : 'Develop my story'),
            ),
            if (writing || assistantJobActive) _busyChip('Writing…'),
            if (hasStory && !approved)
              OutlinedButton.icon(
                onPressed: _approving || _assistantWorking ? null : _approveStory,
                icon: const Icon(Icons.check_circle_outline, size: 18),
                label: Text(_approving ? 'Approving…' : 'Approve story'),
              ),
            if (approved)
              const Text('Your story is approved. Next: build the cast and scenes.',
                  style: TextStyle(color: AppColors.success, fontSize: 12)),
          ]),
        ]),
      ),
      const SizedBox(height: 16),
      Container(
        decoration: studioPanel(),
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (widget.d.project.storyBible != null) ...[
            _StoryPlanCard(widget.d.project.storyBible!),
            const SizedBox(height: 14),
          ],
          const Text('Screenplay', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 4),
          const Text('Review and edit the screenplay before breaking it into scenes.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
          const SizedBox(height: 10),
          TextField(
            controller: _script,
            onChanged: (_) => setState(() {}),
            minLines: 14,
            maxLines: 40,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13.5, height: 1.5),
            decoration: studioField('', hint: 'INT. KITCHEN - NIGHT\n\nMAYA stares at the phone…'),
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
            FilledButton.icon(
              style: _primaryBtn,
              onPressed: splitting || _script.text.trim().isEmpty || approvalRequired ? null : () async {
                if (await _save()) {
                  await widget.run('breakdown',
                      warning: sceneCount > 0
                          ? 'You have $sceneCount scenes. Scenes that haven\'t changed keep their pictures and voice. '
                              'Changed scenes are replaced, and the old versions are saved, not deleted.'
                          : null);
                }
              },
              icon: const Icon(Icons.view_carousel_outlined, size: 18),
              label: const Text('Break into cast & scenes'),
            ),
            if (splitting) _busyChip('Building scenes…'),
            if (approvalRequired)
              const Text('Approve the story above before turning this AI story into scenes.',
                  style: TextStyle(color: AppColors.coin, fontSize: 12)),
            if (sceneCount > 0)
              TextButton(onPressed: () => widget.goTo(2), child: Text('Go to $sceneCount scenes →')),
          ]),
        ]),
      ),
    ]);
  }

  Widget _assistantCostRow(String label, String value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(child: Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13))),
          Text(value, style: TextStyle(
            fontSize: bold ? 15 : 13,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            color: bold ? AppColors.coin : AppColors.textPrimary,
          )),
        ]),
      );

  Widget _assistantBadge(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(20)),
        child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
      );
}

// ================================================================ Cast

class _CastPanel extends StatelessWidget {
  final StudioProjectDetail d;
  final List<StudioVoice> voices;
  final _Run run;
  final _Busy busy;
  final Future<void> Function() reload;
  const _CastPanel(this.d, {required this.voices, required this.run, required this.busy, required this.reload});

  Future<void> _add(BuildContext context) async {
    final name = TextEditingController(), desc = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: StudioColors.panel,
        title: const Text('Add character'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, decoration: studioField('Name')),
            const SizedBox(height: 10),
            TextField(controller: desc, maxLines: 3, decoration: studioField('Looks', hint: 'Age, build, hair, face, usual clothes')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
        ],
      ),
    );
    if (ok == true && name.text.trim().isNotEmpty) {
      try {
        await CreatorStudioService.addCharacter(d.project.id, name.text.trim(), desc.text.trim());
        await reload();
      } on StudioException catch (e) {
        if (context.mounted) showStudioError(context, e.message);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final missing = d.characters.where((c) => c.portraitUrl == null && c.description.trim().isNotEmpty).map((c) => c.id).toList();
    return ListView(padding: const EdgeInsets.fromLTRB(20, 20, 20, 40), children: [
      _sectionHeader('Cast', 'Create each character once and approve their look. Viyo keeps them the same person in every scene.', actions: [
        OutlinedButton.icon(onPressed: () => _add(context), icon: const Icon(Icons.person_add_alt, size: 18), label: const Text('Add character')),
        if (d.characters.isNotEmpty && d.project.script.trim().isNotEmpty)
          OutlinedButton.icon(
            onPressed: busy('outfits') ? null : () => run('outfits'),
            icon: const Icon(Icons.checkroom_outlined, size: 18),
            label: Text(busy('outfits') ? 'Suggesting outfits…' : 'Suggest outfits'),
          ),
        if (missing.isNotEmpty)
          FilledButton.icon(
            style: _primaryBtn,
            onPressed: () => run('portrait', targets: missing),
            icon: const Icon(Icons.auto_awesome, size: 18),
            label: Text('Make ${missing.length} portrait${missing.length == 1 ? '' : 's'}'),
          ),
      ]),
      if (d.characters.isEmpty)
        Container(
          decoration: studioPanel(),
          padding: const EdgeInsets.all(28),
          child: const Column(children: [
            Icon(Icons.groups_outlined, size: 36, color: AppColors.textMuted),
            SizedBox(height: 10),
            Text('No characters yet', style: TextStyle(fontWeight: FontWeight.w700)),
            SizedBox(height: 4),
            Text('Break your script into scenes and the cast is created for you, or add characters by hand.',
                textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
          ]),
        ),
      LayoutBuilder(builder: (ctx, box) {
        final cols = box.maxWidth > 760 ? 2 : 1;
        final w = (box.maxWidth - (cols - 1) * 12) / cols;
        return Wrap(spacing: 12, runSpacing: 12, children: [
          for (final c in d.characters)
            SizedBox(
              width: w,
              child: _CharacterCard(key: ValueKey('${c.id}:${c.portraitUrl}'), c: c, voices: voices,
                  busy: busy('portrait', characterId: c.id), run: run, reload: reload),
            ),
        ]);
      }),
      const SizedBox(height: 16),
      ElementsSection(d: d, run: run, busy: (k) => busy(k), reload: reload),
    ]);
  }
}

class _CharacterCard extends StatefulWidget {
  final StudioCharacter c;
  final List<StudioVoice> voices;
  final bool busy;
  final _Run run;
  final Future<void> Function() reload;
  const _CharacterCard({super.key, required this.c, required this.voices, required this.busy, required this.run, required this.reload});
  @override
  State<_CharacterCard> createState() => _CharacterCardState();
}

class _CharacterCardState extends State<_CharacterCard> {
  late final _name = TextEditingController(text: widget.c.name);
  late final _desc = TextEditingController(text: widget.c.description);
  late String _voice = widget.c.voice;
  late final _style = TextEditingController(text: widget.c.voiceStyle);
  bool _saving = false;

  bool get _voiceDirty => _voice != widget.c.voice || _style.text.trim() != widget.c.voiceStyle;
  bool get _dirty => _name.text != widget.c.name || _desc.text != widget.c.description || _voiceDirty;

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    _style.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final fields = <String, dynamic>{
      'name': _name.text.trim(),
      'description': _desc.text.trim(),
      if (_voice.isNotEmpty) 'voice': _voice,
      'voice_style': _style.text.trim(),
    };
    try {
      List<String> rerecord;
      try {
        rerecord = await CreatorStudioService.updateCharacter(widget.c.id, fields);
      } on StudioException catch (e) {
        if (!e.needsVoiceChangeConfirm || !mounted) rethrow;
        final yes = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: StudioColors.panel,
            title: Text('Change ${widget.c.name}\'s voice?'),
            content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420), child: Text(e.message, style: const TextStyle(height: 1.4))),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep the current voice')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Change voice')),
            ],
          ),
        );
        if (yes != true) {
          if (mounted) {
            setState(() {
              _voice = widget.c.voice;
              _style.text = widget.c.voiceStyle;
            });
          }
          return;
        }
        rerecord = await CreatorStudioService.updateCharacter(widget.c.id, {...fields, 'confirm_voice_change': true});
      }
      await widget.reload();
      if (rerecord.isNotEmpty && mounted) {
        final now = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: StudioColors.panel,
            title: const Text('Re-record with the new voice?'),
            content: Text('${rerecord.length} scene${rerecord.length == 1 ? '' : 's'} still use the old voice. '
                'You\'ll see the price before anything is made.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Later')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('See price')),
            ],
          ),
        );
        if (now == true) widget.run('voice', targets: rerecord);
      }
    } on StudioException catch (e) {
      if (mounted) showStudioError(context, e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: StudioColors.panel,
        title: Text('Remove ${widget.c.name}?'),
        content: const Text('Scenes keep their pictures. You can add the character again later.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true) return;
    await CreatorStudioService.deleteCharacter(widget.c.id);
    await widget.reload();
  }

  @override
  Widget build(BuildContext context) {
    final voiceNames = widget.voices.map((v) => v.name).toSet();
    return Container(
      decoration: studioPanel(),
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
       Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Column(children: [
          AspectFrame(
            vertical: true,
            width: 96,
            imageUrl: widget.c.portraitUrl,
            placeholder: Icons.person_outline,
            overlay: widget.busy ? Container(color: Colors.black54, child: const Center(child: CircularProgressIndicator(strokeWidth: 2.5))) : null,
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: 96,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 6), textStyle: const TextStyle(fontSize: 12)),
              onPressed: widget.busy || _desc.text.trim().isEmpty
                  ? null
                  : () async {
                      if (_dirty) await _save();
                      widget.run('portrait', targets: [widget.c.id]);
                    },
              child: Text(widget.c.portraitUrl == null ? 'Portrait' : 'Redo'),
            ),
          ),
        ]),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: TextField(controller: _name, onChanged: (_) => setState(() {}), decoration: studioField('Name'))),
              IconButton(tooltip: 'Remove', onPressed: _delete, icon: const Icon(Icons.delete_outline, size: 20, color: AppColors.textMuted)),
            ]),
            const SizedBox(height: 8),
            TextField(controller: _desc, onChanged: (_) => setState(() {}), minLines: 2, maxLines: 5,
                decoration: studioField('Looks', hint: 'Age, build, hair, face, clothes')),
            const SizedBox(height: 8),
            VoiceTile(
              voice: widget.voices.where((v) => v.name == _voice).firstOrNull,
              voiceName: voiceNames.contains(_voice) ? _voice : null,
              locked: widget.c.voiceLocked,
              status: _voice != widget.c.voice ? 'manual' : widget.c.voiceStatus,
              ageLabel: widget.c.ageLabel,
              ageYears: widget.c.ageYears,
              onChange: () async {
                final picked = await pickStudioVoice(context, widget.voices, _voice, widget.c.name);
                if (picked != null && mounted) setState(() => _voice = picked);
              },
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _style,
              maxLength: 80,
              onChanged: (_) => setState(() {}),
              decoration: studioField('Delivery note (optional)', hint: 'e.g. calm and low').copyWith(counterText: ''),
            ),
            if (_dirty) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(onPressed: _saving ? null : _save, child: const Text('Save changes')),
              ),
            ],
          ]),
        ),
       ]),
       CharacterIdentitySection(c: widget.c, busy: widget.busy, run: widget.run, reload: widget.reload),
      ]),
    );
  }
}

// ================================================================ Scenes

class _ScenesPanel extends StatelessWidget {
  final StudioProjectDetail d;
  final _Run run;
  final _Busy busy;
  final Future<void> Function() reload;
  final List<StudioEffect> effects;
  final bool lipsync;
  const _ScenesPanel(this.d, {required this.effects, this.lipsync = false, required this.run, required this.busy, required this.reload});

  @override
  Widget build(BuildContext context) {
    final scenes = d.scenes;
    final noImage = scenes.where((s) => !s.hasImage && (s.visual.trim().isNotEmpty || s.heading.trim().isNotEmpty)).map((s) => s.id).toList();
    final noVoice = scenes.where((s) => !s.hasAudio && !(s.mode == 'video' && s.spokenInVideo) && s.dialogue.any((l) => l.text.trim().isNotEmpty)).map((s) => s.id).toList();
    final ready = scenes.where((s) => s.ready).length;
    final noPortraits = d.characters.isNotEmpty && d.characters.every((c) => c.portraitUrl == null);
    return ListView(padding: const EdgeInsets.fromLTRB(20, 20, 20, 60), children: [
      _sectionHeader('Scenes', '${scenes.length} scenes · $ready with pictures · ${scenes.where((s) => s.hasAudio).length} voiced', actions: [
        OutlinedButton.icon(
          onPressed: () async {
            await CreatorStudioService.addScene(d.project.id);
            await reload();
          },
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add scene'),
        ),
        if (noImage.isNotEmpty)
          FilledButton.icon(
            style: _primaryBtn,
            onPressed: () => run('image', targets: noImage,
                warning: noPortraits ? 'Tip: make character portraits first so faces stay the same in every scene.' : null),
            icon: const Icon(Icons.image_outlined, size: 18),
            label: Text('Make ${noImage.length} image${noImage.length == 1 ? '' : 's'}'),
          ),
        if (noVoice.isNotEmpty)
          FilledButton.icon(
            style: _primaryBtn,
            onPressed: () => run('voice', targets: noVoice),
            icon: const Icon(Icons.record_voice_over_outlined, size: 18),
            label: Text('Voice ${noVoice.length} scene${noVoice.length == 1 ? '' : 's'}'),
          ),
      ]),
      if (scenes.isEmpty)
        Container(
          decoration: studioPanel(),
          padding: const EdgeInsets.all(28),
          child: const Column(children: [
            Icon(Icons.view_carousel_outlined, size: 36, color: AppColors.textMuted),
            SizedBox(height: 10),
            Text('No scenes yet', style: TextStyle(fontWeight: FontWeight.w700)),
            SizedBox(height: 4),
            Text('Go to Story and break your script into scenes, or add scenes one by one.',
                textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
          ]),
        ),
      for (var i = 0; i < scenes.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _SceneCard(
            key: ValueKey('${scenes[i].id}:${scenes[i].imageUrl}:${scenes[i].audioUrl}:${scenes[i].videoUrl}'),
            scene: scenes[i],
            index: i,
            count: scenes.length,
            d: d,
            effects: effects,
            lipsync: lipsync,
            run: run,
            busy: busy,
            reload: reload,
          ),
        ),
    ]);
  }
}

class _SceneCard extends StatefulWidget {
  final StudioScene scene;
  final List<StudioEffect> effects;
  final bool lipsync;
  final int index, count;
  final StudioProjectDetail d;
  final _Run run;
  final _Busy busy;
  final Future<void> Function() reload;
  const _SceneCard({super.key, required this.scene, required this.index, required this.count, required this.d,
      this.effects = const [], this.lipsync = false,
      required this.run, required this.busy, required this.reload});
  @override
  State<_SceneCard> createState() => _SceneCardState();
}

class _SceneCardState extends State<_SceneCard> {
  late final _heading = TextEditingController(text: widget.scene.heading);
  late final _visual = TextEditingController(text: widget.scene.visual);
  // (who, line, delivery). Delivery is optional, e.g. "whispering".
  // (who, line, emotion, delivery note). The delivery note comes from Viyo's
  // scene list and is kept as it is when the scene is saved.
  late List<(String, TextEditingController, String, String)> _lines = widget.scene.dialogue
      .map((l) => (l.character, TextEditingController(text: l.text), l.emotion, l.delivery))
      .toList();
  late double _duration = widget.scene.durationSeconds;
  late List<String> _sfx = [...widget.scene.sfx];
  late String _mode = widget.scene.mode;
  bool _saving = false;
  AudioPlayer? _player;
  bool _playing = false;

  @override
  void dispose() {
    _heading.dispose();
    _visual.dispose();
    for (final (_, c, _, _) in _lines) {
      c.dispose();
    }
    _player?.dispose();
    super.dispose();
  }

  bool get _dirty {
    final s = widget.scene;
    final lines = _lines.map((l) => '${l.$1}|${l.$2.text}|${l.$3}|${l.$4}').join('\n');
    final orig = s.dialogue.map((l) => '${l.character}|${l.text}|${l.emotion}|${l.delivery}').join('\n');
    return _heading.text != s.heading || _visual.text != s.visual || lines != orig || _duration != s.durationSeconds || _mode != s.mode ||
        _sfx.join(',') != s.sfx.join(',');
  }

  Future<bool> _save() async {
    if (!_dirty) return true;
    setState(() => _saving = true);
    try {
      await CreatorStudioService.updateScene(widget.scene.id, {
        'heading': _heading.text, 'visual': _visual.text, 'duration_seconds': _duration, 'mode': _mode, 'sfx': _sfx,
        'dialogue': [
          for (final (ch, c, mood, delivery) in _lines)
            if (c.text.trim().isNotEmpty) StudioLine(ch, c.text.trim(), mood, delivery).toJson()
        ],
      });
      await widget.reload();
      return true;
    } on StudioException catch (e) {
      if (mounted) showStudioError(context, e.message);
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _move(int delta) async {
    final ids = widget.d.scenes.map((s) => s.id).toList();
    final i = widget.index, j = i + delta;
    if (j < 0 || j >= ids.length) return;
    final t = ids[i];
    ids[i] = ids[j];
    ids[j] = t;
    await CreatorStudioService.reorderScenes(widget.d.project.id, ids);
    await widget.reload();
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: StudioColors.panel,
        title: Text('Delete scene ${widget.index + 1}?'),
        content: const Text('Its pictures and voices stay in your project history.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    await CreatorStudioService.deleteScene(widget.scene.id);
    await widget.reload();
  }

  Future<void> _toggleAudio() async {
    final url = widget.scene.audioUrl;
    if (url == null) return;
    _player ??= AudioPlayer()..onPlayerComplete.listen((_) => mounted ? setState(() => _playing = false) : null);
    if (_playing) {
      await _player!.stop();
      setState(() => _playing = false);
    } else {
      await _player!.play(UrlSource(url));
      setState(() => _playing = true);
    }
  }

  Future<void> _runFor(String kind) async {
    if (await _save()) widget.run(kind, targets: [widget.scene.id]);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.scene;
    final vertical = widget.d.project.vertical;
    final names = ['NARRATOR', ...widget.d.characters.map((c) => c.name)];
    final imgBusy = widget.busy('image', sceneId: s.id), voiceBusy = widget.busy('voice', sceneId: s.id), vidBusy = widget.busy('video', sceneId: s.id);
    final media = AspectFrame(
      vertical: vertical,
      width: vertical ? 132 : 220,
      imageUrl: s.imageUrl,
      overlay: Stack(children: [
        if (imgBusy || vidBusy) Container(color: Colors.black54, child: const Center(child: CircularProgressIndicator(strokeWidth: 2.5))),
        Positioned(left: 6, top: 6, child: _badge('${widget.index + 1}')),
        if (s.hasVideo) Positioned(right: 6, top: 6, child: _badge('VIDEO', color: AppColors.secondary)),
      ]),
    );
    final actions = Wrap(spacing: 6, runSpacing: 6, children: [
      _act(Icons.image_outlined, s.hasImage ? 'New image' : 'Make image', imgBusy ? null : () => _runFor('image')),
      if (!(_mode == 'video' && s.spokenInVideo))
        _act(Icons.record_voice_over_outlined, s.voiceOutdated.isNotEmpty ? 'Re-record' : (s.hasAudio ? 'Re-voice' : 'Voice'),
            voiceBusy || _lines.every((l) => l.$2.text.trim().isEmpty) ? null : () => _runFor('voice')),
      if (s.speech == 'lipsync' && s.hasAudio)
        _act(Icons.record_voice_over, s.hasLipsync ? 'Redo lip sync' : 'Lip sync',
            widget.busy('lipsync', sceneId: s.id) ? null : () => _runFor('lipsync')),
      if (_mode == 'video')
        _act(Icons.videocam_outlined,
            s.spokenInVideo && _lines.any((l) => l.$2.text.trim().isNotEmpty)
                ? (s.hasVideo ? 'New talking video' : 'Make talking video')
                : (s.hasVideo ? 'New AI video' : 'Make AI video'),
            vidBusy ? null : () => _runFor('video')),
      if (s.audioUrl != null) _act(_playing ? Icons.stop : Icons.play_arrow, _playing ? 'Stop' : 'Play voice', _toggleAudio),
    ]);
    final editor = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: TextField(controller: _heading, onChanged: (_) => setState(() {}), decoration: studioField('Scene', hint: 'INT. ROOFTOP - NIGHT'))),
        IconButton(tooltip: 'Move up', onPressed: widget.index == 0 ? null : () => _move(-1), icon: const Icon(Icons.arrow_upward, size: 18)),
        IconButton(tooltip: 'Move down', onPressed: widget.index == widget.count - 1 ? null : () => _move(1), icon: const Icon(Icons.arrow_downward, size: 18)),
        IconButton(tooltip: 'Delete scene', onPressed: _delete, icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.textMuted)),
      ]),
      const SizedBox(height: 8),
      TextField(controller: _visual, onChanged: (_) => setState(() {}), minLines: 2, maxLines: 5,
          decoration: studioField('What we see', hint: 'Who is in frame, what they do, the place, the light, the camera')),
      const SizedBox(height: 10),
      for (var i = 0; i < _lines.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(children: [
            SizedBox(
              width: MediaQuery.of(context).size.width < 500 ? 112 : 150,
              child: DropdownButtonFormField<String>(
                initialValue: names.firstWhere((n) => n.toLowerCase() == _lines[i].$1.toLowerCase(), orElse: () => 'NARRATOR'),
                isExpanded: true,
                dropdownColor: StudioColors.panel,
                decoration: studioField('Who'),
                items: [for (final n in names) DropdownMenuItem(value: n, child: Text(n, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)))],
                onChanged: (v) => setState(() => _lines[i] = (v ?? 'NARRATOR', _lines[i].$2, _lines[i].$3, _lines[i].$4)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: _lines[i].$2, onChanged: (_) => setState(() {}), decoration: studioField('Line'))),
            _moodButton(i),
            IconButton(
              tooltip: 'Remove line',
              onPressed: () => setState(() {
                _lines[i].$2.dispose();
                _lines = [..._lines]..removeAt(i);
              }),
              icon: const Icon(Icons.close, size: 18, color: AppColors.textMuted),
            ),
          ]),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: _lines.length >= 12 ? null : () => setState(() => _lines = [..._lines, (names.length > 1 ? names[1] : 'NARRATOR', TextEditingController(), '', '')]),
          icon: const Icon(Icons.add_comment_outlined, size: 18),
          label: const Text('Add line'),
        ),
      ),
      const SizedBox(height: 6),
      Wrap(spacing: 14, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        SegmentedButton<String>(
          style: SegmentedButton.styleFrom(visualDensity: VisualDensity.compact),
          segments: const [
            ButtonSegment(value: 'still', icon: Icon(Icons.photo_outlined, size: 16), label: Text('Still')),
            ButtonSegment(value: 'video', icon: Icon(Icons.videocam_outlined, size: 16), label: Text('AI video')),
          ],
          selected: {_mode},
          onSelectionChanged: (v) => setState(() => _mode = v.first),
        ),
        SizedBox(
          width: 240,
          child: Row(children: [
            Text('${_duration.toStringAsFixed(0)} s', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            Expanded(child: Slider(value: _duration, min: 2, max: 20, divisions: 18, onChanged: (v) => setState(() => _duration = v))),
          ]),
        ),
        if (s.audioSeconds != null) Text('Voice ${s.audioSeconds!.toStringAsFixed(1)} s', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
      ]),
      const SizedBox(height: 8),
      if ((_mode == 'video' || widget.lipsync || s.speech == 'lipsync') && _lines.any((l) => l.$2.text.trim().isNotEmpty)) ...[
        Wrap(spacing: 10, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          const Text('Who speaks', style: TextStyle(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
          SegmentedButton<String>(
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(visualDensity: VisualDensity.compact),
            segments: [
              if (_mode == 'video') const ButtonSegment(value: 'video_model', label: Text('Characters talk in the video')),
              const ButtonSegment(value: 'saved_voice', label: Text('Saved voices')),
              if (widget.lipsync || s.speech == 'lipsync')
                const ButtonSegment(value: 'lipsync', label: Text('Saved voices + lip sync')),
            ],
            selected: {s.speech},
            onSelectionChanged: (v) => _setSpeech(v.first),
          ),
        ]),
        const SizedBox(height: 4),
        Text(
          switch (s.speech) {
            'video_model' => 'Lips move with the words. The video model makes the voice from each character\'s voice '
                'description, so it can sound a little different between scenes.',
            'lipsync' => 'Each character\'s permanent voice, and their lips are made to match it. Record the voices, '
                'make the video, then press Lip sync.${s.hasLipsync ? ' Lip sync done.' : ''}',
            _ => 'Each character\'s permanent voice is used. Lips don\'t move with the words.',
          },
          style: const TextStyle(fontSize: 12, color: AppColors.textMuted, height: 1.35),
        ),
        const SizedBox(height: 8),
      ],
      _lookRow(s),
      if (s.consistency.isNotEmpty) ...[
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(color: AppColors.coin.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.coin.withValues(alpha: 0.35))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.face_retouching_natural, size: 16, color: AppColors.coin),
            const SizedBox(width: 8),
            Expanded(
              child: Text(s.consistency.join('\n'), style: const TextStyle(fontSize: 12.5, color: AppColors.coin, height: 1.3)),
            ),
          ]),
        ),
        const SizedBox(height: 8),
      ],
      if (s.madeWithReferences.isNotEmpty && s.consistency.isEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Tooltip(
            message: s.madeWithReferences.join('\n'),
            child: Row(children: [
              const Icon(Icons.verified_user_outlined, size: 14, color: AppColors.success),
              const SizedBox(width: 6),
              Text('Made with ${s.madeWithReferences.length} reference picture${s.madeWithReferences.length == 1 ? '' : 's'}',
                  style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
            ]),
          ),
        ),
      if (s.voiceOutdated.isNotEmpty) ...[
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(color: AppColors.coin.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.coin.withValues(alpha: 0.35))),
          child: Row(children: [
            const Icon(Icons.record_voice_over_outlined, size: 16, color: AppColors.coin),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Recorded with ${s.voiceOutdated.join(' and ')}\'s old voice. Re-record to use the new one.',
                  style: const TextStyle(fontSize: 12.5, color: AppColors.coin, height: 1.3)),
            ),
          ]),
        ),
        const SizedBox(height: 8),
      ],
      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        actions,
        if (_dirty) FilledButton(onPressed: _saving ? null : _save, child: const Text('Save')),
        if (voiceBusy) _busyChip('Voicing…'),
      ]),
      if (widget.effects.isNotEmpty) ...[
        const SizedBox(height: 10),
        const Text('Sound effects', style: TextStyle(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final e in widget.effects)
            FilterChip(
              visualDensity: VisualDensity.compact,
              label: Text(e.label, style: const TextStyle(fontSize: 12)),
              selected: _sfx.contains(e.id),
              onSelected: (on) => setState(() {
                if (on && _sfx.length < 4) {
                  _sfx = [..._sfx, e.id];
                } else if (!on) {
                  _sfx = _sfx.where((x) => x != e.id).toList();
                }
              }),
            ),
        ]),
      ],
    ]);
    return Container(
      decoration: studioPanel(border: s.ready ? null : AppColors.coin.withValues(alpha: 0.25)),
      padding: const EdgeInsets.all(12),
      child: LayoutBuilder(builder: (ctx, box) {
        if (box.maxWidth < 560) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Center(child: media), const SizedBox(height: 10), editor]);
        }
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [media, const SizedBox(width: 14), Expanded(child: editor)]);
      }),
    );
  }

  static const _cameras = {
    'auto': 'Camera: automatic', 'close_up': 'Close-up', 'front': 'Facing camera', 'side': 'Side view',
    'back': 'From behind', 'full_body': 'Full body', 'wide': 'Wide shot',
  };

  /// Characters named in this scene (the same rule the backend uses).
  List<StudioCharacter> _inScene(StudioScene s) {
    final text = [s.visual, s.heading, ...s.dialogue.map((l) => l.character)].join(' ').toLowerCase();
    return widget.d.characters
        .where((c) => c.name.isNotEmpty && RegExp('\\b${RegExp.escape(c.name.toLowerCase())}\\b').hasMatch(text))
        .toList();
  }

  /// Camera framing and, for characters with more than one outfit, what they wear.
  Widget _lookRow(StudioScene s) {
    final dressed = _inScene(s).where((c) => c.outfits.isNotEmpty).toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        PopupMenuButton<String>(
          tooltip: 'Camera framing',
          color: StudioColors.panel,
          onSelected: (v) => _setLook({'camera': v}),
          itemBuilder: (_) => [for (final e in _cameras.entries) PopupMenuItem(value: e.key, child: Text(e.value))],
          child: Chip(
            visualDensity: VisualDensity.compact,
            avatar: const Icon(Icons.videocam_outlined, size: 16),
            label: Text(s.camera == 'auto' ? 'Camera: ${_cameras[s.cameraUsed] ?? 'automatic'}' : _cameras[s.camera]!,
                style: const TextStyle(fontSize: 12)),
          ),
        ),
        if (widget.d.elements.any((e) => e.isPlace))
          PopupMenuButton<String>(
            tooltip: 'Where this scene happens',
            color: StudioColors.panel,
            onSelected: (v) => _setLook({'location_id': v}),
            itemBuilder: (_) => [
              const PopupMenuItem(value: '', child: Text('Automatic (from the scene heading)')),
              for (final e in widget.d.elements.where((e) => e.isPlace)) PopupMenuItem(value: e.id, child: Text(e.name)),
            ],
            child: Chip(
              visualDensity: VisualDensity.compact,
              avatar: const Icon(Icons.place_outlined, size: 16),
              label: Text('Place: ${s.locationUsed ?? 'none'}', style: const TextStyle(fontSize: 12)),
            ),
          ),
        if (widget.d.elements.any((e) => !e.isPlace))
          ActionChip(
            visualDensity: VisualDensity.compact,
            avatar: const Icon(Icons.category_outlined, size: 16),
            label: Text(s.propsUsed.isEmpty ? 'Objects: none' : 'Objects: ${s.propsUsed.join(', ')}',
                style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
            onPressed: () => _pickProps(s),
          ),
        for (final c in dressed)
          PopupMenuButton<String>(
            tooltip: 'What ${c.name} wears',
            color: StudioColors.panel,
            onSelected: (v) => v == '__scene_only__'
                ? _sceneOnly(s, c)
                : _setLook({'outfits': {...s.outfits, c.id: v}..removeWhere((_, x) => x.isEmpty)}),
            itemBuilder: (_) => [
              const PopupMenuItem(value: '', child: Text('Same as the scene before')),
              for (final o in c.outfits) PopupMenuItem(value: o.id, child: Text(o.name)),
              const PopupMenuDivider(),
              const PopupMenuItem(value: '__scene_only__', child: Text('Change for this scene only…')),
            ],
            child: Chip(
              visualDensity: VisualDensity.compact,
              avatar: const Icon(Icons.checkroom_outlined, size: 16),
              label: Text(
                  '${c.name}: ${c.outfits.where((o) => o.id == s.outfits[c.id]).map((o) => o.name).firstOrNull ?? 'same as before'}'
                  '${(s.outfitOverrides[c.id] ?? const {}).isNotEmpty ? ' + scene change' : ''}',
                  style: const TextStyle(fontSize: 12)),
            ),
          ),
      ]),
    );
  }

  /// A change for this scene only (e.g. smudged makeup), part by part, on top
  /// of the outfit. The saved outfit and the next scene are not changed.
  Future<void> _sceneOnly(StudioScene s, StudioCharacter c) async {
    final current = s.outfitOverrides[c.id] ?? const {};
    final ctl = {for (final k in StudioOutfit.parts) k: TextEditingController(text: current[k] ?? '')};
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: StudioColors.panel,
        title: Text('${c.name} in this scene only'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('Fill in only what changes. The outfit, the other scenes, and the face and body stay the same.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.35)),
              const SizedBox(height: 10),
              for (final k in StudioOutfit.parts) ...[
                TextField(controller: ctl[k], maxLength: 300,
                    decoration: studioField(StudioOutfit.partLabels[k]!, hint: 'Leave empty to keep the outfit\'s').copyWith(counterText: '')),
                const SizedBox(height: 8),
              ],
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    final parts = {for (final e in ctl.entries) if (e.value.text.trim().isNotEmpty) e.key: e.value.text.trim()};
    for (final x in ctl.values) {
      x.dispose();
    }
    if (ok != true) return;
    final all = {...s.outfitOverrides, c.id: parts}..removeWhere((_, v) => v.isEmpty);
    await _setLook({'outfit_overrides': all});
  }

  /// The scene's objects: automatic (from the text) or exactly the ticked ones.
  Future<void> _pickProps(StudioScene s) async {
    final objects = widget.d.elements.where((e) => !e.isPlace).toList();
    final chosen = <String>{...(s.propIds ?? widget.d.elements.where((e) => s.propsUsed.contains(e.name)).map((e) => e.id))};
    var auto = s.propIds == null;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          backgroundColor: StudioColors.panel,
          title: Text('Objects in scene ${widget.index + 1}'),
          content: SizedBox(
            width: 380,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: auto,
                  onChanged: (v) => setDialog(() => auto = v),
                  title: const Text('Automatic', style: TextStyle(fontSize: 13.5)),
                  subtitle: const Text('Use the objects the scene mentions.', style: TextStyle(fontSize: 11.5)),
                ),
                if (!auto)
                  for (final o in objects)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: chosen.contains(o.id),
                      title: Text(o.name, style: const TextStyle(fontSize: 13)),
                      onChanged: (v) => setDialog(() => v == true ? chosen.add(o.id) : chosen.remove(o.id)),
                    ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await _setLook(auto ? {'props_auto': true} : {'props': chosen.toList()});
  }

  Future<void> _setLook(Map<String, dynamic> fields) async {
    if (!await _save()) return;
    try {
      await CreatorStudioService.updateScene(widget.scene.id, fields);
      await widget.reload();
    } on StudioException catch (e) {
      if (mounted) showStudioError(context, e.message);
    }
  }

  Future<void> _setSpeech(String value) async {
    if (!await _save()) return;
    try {
      await CreatorStudioService.updateScene(widget.scene.id, {'speech': value});
      await widget.reload();
    } on StudioException catch (e) {
      if (mounted) showStudioError(context, e.message);
    }
  }

  static const _moods = ['calm', 'happy', 'sad', 'angry', 'scared', 'whispering', 'shouting', 'crying', 'sarcastic', 'tender'];

  Widget _moodButton(int i) {
    final mood = _lines[i].$3;
    return PopupMenuButton<String>(
      tooltip: 'How it is said',
      color: StudioColors.panel,
      onSelected: (v) => setState(() => _lines[i] = (_lines[i].$1, _lines[i].$2, v, _lines[i].$4)),
      itemBuilder: (_) => [
        const PopupMenuItem(value: '', child: Text('Plain (no direction)')),
        if (mood.isNotEmpty && !_moods.contains(mood)) PopupMenuItem(value: mood, child: Text(mood)),
        for (final m in _moods) PopupMenuItem(value: m, child: Text(m)),
      ],
      child: Padding(
        padding: const EdgeInsets.only(left: 6),
        child: mood.isEmpty
            ? const Icon(Icons.theater_comedy_outlined, size: 20, color: AppColors.textMuted)
            : Container(
                constraints: const BoxConstraints(maxWidth: 96),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: AppColors.secondary.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
                child: Text(mood, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
              ),
      ),
    );
  }

  Widget _badge(String t, {Color color = Colors.black87}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
        child: Text(t, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white)),
      );

  Widget _act(IconData icon, String label, VoidCallback? onTap) => OutlinedButton.icon(
        style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact, textStyle: const TextStyle(fontSize: 12.5)),
        onPressed: onTap,
        icon: Icon(icon, size: 16),
        label: Text(label),
      );
}

// ================================================================ Export

class _ExportPanel extends StatefulWidget {
  final StudioProjectDetail d;
  final _Run run;
  final _Busy busy;
  final Future<void> Function() reload;
  final Future<void> Function() onNeedCredits;
  const _ExportPanel(this.d, {required this.run, required this.busy, required this.reload, required this.onNeedCredits});
  @override
  State<_ExportPanel> createState() => _ExportPanelState();
}

class _ExportPanelState extends State<_ExportPanel> {
  /// The poster people see before they tap. The AI designs it from the story
  /// (any characters, or none) with the title in the art and a small Viyo mark.
  /// Every cover is kept; the creator picks the main one.
  Future<void> _makeCover(StudioProjectDetail d) async {
    final idea = TextEditingController();
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: StudioColors.panel,
        title: Text(d.project.covers.isEmpty ? 'Make a cover' : 'Make another cover'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('The AI reads your story and designs the poster: the right characters, or a place or object '
                'if that tells the story better, with the title in the art.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12.5, height: 1.4)),
            const SizedBox(height: 12),
            TextField(controller: idea, maxLength: 300, maxLines: 2,
                decoration: studioField('Your idea (optional)', hint: 'e.g. show the two sisters back to back in the rain')
                    .copyWith(counterText: '')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Next')),
        ],
      ),
    );
    final note = idea.text.trim();
    idea.dispose();
    if (go != true) return;
    widget.run('cover', extra: {if (note.isNotEmpty) 'cover_note': note});
  }

  Future<void> _openCover(StudioProjectDetail d, Map<String, dynamic> c) async {
    final main = c['is_main'] == true;
    final pick = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: StudioColors.panel,
        contentPadding: const EdgeInsets.all(12),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420, maxHeight: 600),
          child: ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.network('${c['url']}', fit: BoxFit.contain)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Close')),
          if (!main) FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Use as main cover')),
        ],
      ),
    );
    if (pick != true) return;
    try {
      await CreatorStudioService.chooseCover(d.project.id, '${c['id']}');
      await widget.reload();
      if (mounted) showStudioInfo(context, 'Main cover changed.');
    } on StudioException catch (e) {
      if (mounted) showStudioError(context, e.message);
    }
  }

  Widget _coverPanel(StudioProjectDetail d) {
    final making = widget.busy('cover');
    final covers = d.project.covers;
    return Container(
      decoration: studioPanel(),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Expanded(child: Text('Covers', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
          FilledButton.icon(
            style: _primaryBtn,
            onPressed: making ? null : () => _makeCover(d),
            icon: const Icon(Icons.auto_awesome, size: 18),
            label: Text(making ? 'Making…' : covers.isEmpty ? 'Make cover' : 'Make another'),
          ),
        ]),
        const SizedBox(height: 4),
        const Text('The poster for your movie or drama, designed by AI from your story, with the title and a small '
            'Viyo mark. The main cover is what viewers see.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.35)),
        if (covers.isNotEmpty || making) ...[
          const SizedBox(height: 12),
          SizedBox(
            height: 170,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              if (making)
                Container(
                  width: 112,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(color: const Color(0xFF17173A), borderRadius: BorderRadius.circular(10)),
                  child: const Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
                ),
              for (final c in covers)
                GestureDetector(
                  onTap: () => _openCover(d, c),
                  child: Container(
                    width: 112,
                    margin: const EdgeInsets.only(right: 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: c['is_main'] == true ? AppColors.primary : Colors.transparent, width: 2),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Stack(fit: StackFit.expand, children: [
                        Image.network('${c['url']}', fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(Icons.image_outlined, color: AppColors.textMuted)),
                        if (c['is_main'] == true)
                          Positioned(
                            left: 6,
                            bottom: 6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(8)),
                              child: const Text('Main', style: TextStyle(color: Colors.black, fontSize: 10.5, fontWeight: FontWeight.w800)),
                            ),
                          ),
                      ]),
                    ),
                  ),
                ),
            ]),
          ),
        ],
      ]),
    );
  }

  final Map<String, double?> _progress = {};
  bool _publishing = false;

  /// Posts this version to Viyo after the creator picks the price.
  Future<void> _publish(StudioProjectDetail d, StudioRender r) async {
    final caption = TextEditingController();
    final price = TextEditingController(text: '30');
    var free = true;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          backgroundColor: StudioColors.panel,
          title: const Text('Publish to Viyo'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  'Goes live now on your profile, your drama\'s page in Dramas, and the feed. '
                  '${d.project.coverUrl != null ? 'Your main cover is the poster.' : 'Tip: make a cover first so viewers see a poster.'}',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5, height: 1.4),
                ),
                const SizedBox(height: 14),
                const Text('Price for viewers', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: true, label: Text('Free')),
                    ButtonSegment(value: false, label: Text('Coins per episode')),
                  ],
                  selected: {free},
                  onSelectionChanged: (v) => setDialog(() => free = v.first),
                ),
                if (!free) ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: price,
                    keyboardType: TextInputType.number,
                    decoration: studioField('Coins per episode', hint: 'e.g. 30'),
                  ),
                  const SizedBox(height: 4),
                  const Text('As on every Viyo drama, the first episodes are free so viewers get hooked.',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
                ],
                const SizedBox(height: 12),
                TextField(controller: caption, maxLength: 500, maxLines: 2,
                    decoration: studioField('Caption (optional)').copyWith(counterText: '')),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Publish now')),
          ],
        ),
      ),
    );
    final coins = free ? 0 : (int.tryParse(price.text.trim()) ?? 30).clamp(1, 500);
    final text = caption.text.trim();
    caption.dispose();
    price.dispose();
    if (go != true) return;
    setState(() => _publishing = true);
    try {
      final out = await CreatorStudioService.publishRender(r.id, coinPrice: coins, caption: text);
      await widget.reload();
      if (mounted) showStudioInfo(context, 'Published as episode ${out['episode_number']}. It\'s live on Viyo.');
    } on StudioException catch (e) {
      if (mounted) showStudioError(context, e.message);
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  Future<void> _download(StudioRender r) async {
    setState(() => _progress[r.id] = null);
    try {
      final path = await saver.saveFromUrl(
        freshUrl: () => CreatorStudioService.renderLink(r.id),
        onProgress: (got, total) => mounted ? setState(() => _progress[r.id] = total == null ? null : got / total) : null,
      );
      if (!mounted) return;
      if (saver.savesInBrowser) {
        showStudioInfo(context, 'Download started — check your browser downloads.');
      } else if (path != null) {
        await saver.shareSavedFile(path, 'video/mp4');
      }
    } catch (e) {
      if (mounted) showStudioError(context, 'Download failed. Tap Download to try again.');
    } finally {
      if (mounted) setState(() => _progress.remove(r.id));
    }
  }

  Future<void> _preview(StudioRender r) async {
    try {
      final (url, _) = await CreatorStudioService.renderLink(r.id);
      if (!mounted) return;
      await showDialog(context: context, builder: (_) => _PreviewDialog(url: url, vertical: r.aspectRatio == '9:16'));
    } on StudioException catch (e) {
      if (mounted) showStudioError(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.d;
    final scenes = d.scenes;
    final ready = scenes.where((s) => s.ready).length;
    final voiced = scenes.where((s) => s.hasAudio).length;
    final withLines = scenes.where((s) => s.dialogue.any((l) => l.text.trim().isNotEmpty)).length;
    final runtime = scenes.fold<double>(0, (t, s) => t + (s.audioSeconds != null && s.audioSeconds! + 0.5 > s.durationSeconds ? s.audioSeconds! + 0.5 : s.durationSeconds));
    final rendering = widget.busy('render');
    final canRender = scenes.isNotEmpty && ready == scenes.length;
    return ListView(padding: const EdgeInsets.fromLTRB(20, 20, 20, 40), children: [
      _sectionHeader('Export', '${d.project.vertical ? '1080×1920 vertical' : '1920×1080 landscape'} MP4 · captions ${d.project.captions ? 'on' : 'off'}'),
      ProductionPanel(d: d, reload: widget.reload, onNeedCredits: widget.onNeedCredits),
      const SizedBox(height: 14),
      _coverPanel(d),
      const SizedBox(height: 14),
      Container(
        decoration: studioPanel(),
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _check(scenes.isNotEmpty, 'Scenes', scenes.isEmpty ? 'No scenes yet' : '${scenes.length} scenes · about ${runtime.round()} s'),
          _check(canRender, 'Pictures', '$ready of ${scenes.length} scenes have a picture or AI video'),
          _check(voiced >= withLines, 'Voices', withLines == 0 ? 'No dialogue (music-free silent scenes)' : '$voiced of $withLines scenes with lines are voiced',
              optional: true),
          const SizedBox(height: 14),
          Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
            FilledButton.icon(
              style: _primaryBtn,
              onPressed: canRender && !rendering ? () => widget.run('render') : null,
              icon: const Icon(Icons.movie_creation_outlined, size: 18),
              label: Text(d.renders.isEmpty ? 'Render film' : 'Render new version'),
            ),
            if (rendering) _busyChip('Rendering… this can take a few minutes'),
          ]),
        ]),
      ),
      const SizedBox(height: 16),
      _SoundQualityCard(d.project, reload: widget.reload),
      const SizedBox(height: 18),
      const Text('Versions', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
      const SizedBox(height: 8),
      if (d.renders.isEmpty)
        const Text('Your rendered films appear here. Every version is kept.', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
      for (final r in d.renders)
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: studioPanel(),
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
           Row(children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
              child: Center(child: Text('v${r.version}', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800))),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${r.width}×${r.height} · ${_dur(r.durationSeconds)} · ${_size(r.bytes)}', style: const TextStyle(fontWeight: FontWeight.w600)),
                if (r.createdAt != null)
                  Text(_when(r.createdAt!), style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                if (_progress.containsKey(r.id)) ...[
                  const SizedBox(height: 6),
                  LinearProgressIndicator(value: _progress[r.id], minHeight: 3),
                ],
              ]),
            ),
            IconButton(tooltip: 'Preview', onPressed: () => _preview(r), icon: const Icon(Icons.play_circle_outline)),
           ]),
           const SizedBox(height: 8),
           Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            FilledButton.tonalIcon(
              onPressed: _progress.containsKey(r.id) ? null : () => _download(r),
              icon: const Icon(Icons.download, size: 18),
              label: const Text('Download'),
            ),
            if (r.published)
              const Chip(
                visualDensity: VisualDensity.compact,
                avatar: Icon(Icons.check_circle, size: 16, color: AppColors.success),
                label: Text('Published on Viyo', style: TextStyle(fontSize: 12)),
              )
            else
              FilledButton.icon(
                style: _primaryBtn,
                onPressed: _publishing ? null : () => _publish(d, r),
                icon: const Icon(Icons.public, size: 18),
                label: Text(_publishing ? 'Publishing…' : 'Publish to Viyo'),
              ),
           ]),
          ]),
        ),
      const SizedBox(height: 14),
      Container(
        decoration: studioPanel(),
        padding: const EdgeInsets.all(14),
        child: const Text(
          'Your film is yours to post anywhere — YouTube, TikTok, Instagram, Facebook or Viyo. '
          'To put it on Viyo Watch, download it and upload it from Create → Upload Drama, Movie or Film. '
          'Viyo keeps your project files and every rendered version.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5, height: 1.45),
        ),
      ),
    ]);
  }

  Widget _check(bool ok, String title, String detail, {bool optional = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Icon(ok ? Icons.check_circle : (optional ? Icons.info_outline : Icons.radio_button_unchecked),
              color: ok ? AppColors.success : (optional ? AppColors.textMuted : AppColors.coin), size: 20),
          const SizedBox(width: 10),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(width: 10),
          Expanded(child: Text(detail, style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5))),
        ]),
      );

  String _dur(double s) => s >= 60 ? '${s ~/ 60}:${(s % 60).round().toString().padLeft(2, '0')}' : '${s.toStringAsFixed(1)} s';
  String _size(int? b) => b == null ? '' : b > 1e6 ? '${(b / 1e6).toStringAsFixed(1)} MB' : '${(b / 1e3).round()} KB';
  String _when(DateTime t) {
    final l = t.toLocal();
    return '${l.day}/${l.month}/${l.year} ${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }
}

class _PreviewDialog extends StatefulWidget {
  final String url;
  final bool vertical;
  const _PreviewDialog({required this.url, required this.vertical});
  @override
  State<_PreviewDialog> createState() => _PreviewDialogState();
}

class _PreviewDialogState extends State<_PreviewDialog> {
  late final VideoPlayerController _c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
  bool _ready = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _c.initialize().then((_) {
      if (!mounted) return;
      setState(() => _ready = true);
      _c.play();
    }).catchError((_) {
      if (mounted) setState(() => _error = "Couldn't play the preview. Try Download instead.");
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final maxH = size.height * 0.8;
    final w = widget.vertical ? maxH * 9 / 16 : (size.width * 0.8).clamp(0, 1100).toDouble();
    return Dialog(
      backgroundColor: Colors.black,
      child: SizedBox(
        width: w,
        child: AspectRatio(
          aspectRatio: widget.vertical ? 9 / 16 : 16 / 9,
          child: _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: AppColors.textSecondary)))
              : !_ready
                  ? const Center(child: CircularProgressIndicator())
                  : GestureDetector(
                      onTap: () => setState(() => _c.value.isPlaying ? _c.pause() : _c.play()),
                      child: Stack(alignment: Alignment.bottomCenter, children: [
                        VideoPlayer(_c),
                        VideoProgressIndicator(_c, allowScrubbing: true),
                      ]),
                    ),
        ),
      ),
    );
  }
}

// ================================================================ Activity

class _ActivityPanel extends StatelessWidget {
  final StudioProjectDetail d;
  final Future<void> Function(StudioJob) onCancel;
  const _ActivityPanel(this.d, {required this.onCancel});

  String _target(StudioJob j) {
    if (j.sceneId != null) {
      final i = d.scenes.indexWhere((s) => s.id == j.sceneId);
      return i >= 0 ? 'Scene ${i + 1}' : 'Scene';
    }
    if (j.characterId != null) {
      final c = d.characters.where((c) => c.id == j.characterId);
      return c.isNotEmpty ? c.first.name : 'Character';
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final jobs = d.jobs;
    final spent = jobs.fold<int>(0, (t, j) => t + j.chargedCredits);
    return ListView(padding: const EdgeInsets.fromLTRB(16, 18, 16, 24), children: [
      const Text('Activity', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      const SizedBox(height: 4),
      Text('${creditsLabel(spent)} spent on this production (${usdOf(spent)})',
          style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
      const SizedBox(height: 12),
      if (jobs.isEmpty) const Text('Nothing yet. Everything you start shows here.', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
      for (final j in jobs)
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(10),
          decoration: studioPanel(border: j.status == 'failed' ? AppColors.danger.withValues(alpha: 0.4) : null),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.only(top: 2), child: _statusIcon(j)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${kindTitle(j.kind)}${_target(j).isEmpty ? '' : ' · ${_target(j)}'}',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 2),
                Text(_statusText(j), style: TextStyle(fontSize: 12, color: j.status == 'failed' ? AppColors.danger : AppColors.textMuted)),
              ]),
            ),
            if (j.status == 'queued')
              TextButton(onPressed: () => onCancel(j), child: const Text('Cancel', style: TextStyle(fontSize: 12))),
          ]),
        ),
    ]);
  }

  Widget _statusIcon(StudioJob j) => switch (j.status) {
        'running' => const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
        'queued' => const Icon(Icons.schedule, size: 18, color: AppColors.textMuted),
        'succeeded' => const Icon(Icons.check_circle, size: 18, color: AppColors.success),
        'failed' => const Icon(Icons.error_outline, size: 18, color: AppColors.danger),
        _ => const Icon(Icons.block, size: 18, color: AppColors.textMuted),
      };

  String _statusText(StudioJob j) => switch (j.status) {
        'queued' => 'Waiting · ${creditsLabel(j.estimatedCredits)} reserved',
        'running' => 'Making… · ${creditsLabel(j.estimatedCredits)} reserved',
        'succeeded' => 'Done · ${creditsLabel(j.chargedCredits)}',
        'failed' => '${j.error ?? 'Failed'} Credits returned.',
        _ => 'Cancelled · credits returned',
      };
}


// ================================================================ Sound & quality

class _SoundQualityCard extends StatefulWidget {
  final StudioProject p;
  final Future<void> Function() reload;
  const _SoundQualityCard(this.p, {required this.reload});
  @override
  State<_SoundQualityCard> createState() => _SoundQualityCardState();
}

class _SoundQualityCardState extends State<_SoundQualityCard> {
  late double _volume = widget.p.musicVolume;
  bool _uploading = false;

  Future<void> _pickMusic() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: StudioColors.panel,
        title: const Text('Add background music'),
        content: const Text('Only use music you made or have a licence for. Songs from artists or streaming apps '
            'can get your film blocked on YouTube, TikTok and Viyo.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('I have the rights')),
        ],
      ),
    );
    if (ok != true) return;
    final picked = await FilePicker.platform.pickFiles(type: FileType.audio, withData: true);
    final f = picked?.files.single;
    if (f == null || f.bytes == null) return;
    setState(() => _uploading = true);
    try {
      await CreatorStudioService.uploadMusic(widget.p.id, f.bytes!, f.name);
      await widget.reload();
      if (mounted) showStudioInfo(context, 'Music added. It plays under the whole film and drops when people speak.');
    } on StudioException catch (e) {
      if (mounted) showStudioError(context, e.message);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _save(Map<String, dynamic> fields) async {
    try {
      await CreatorStudioService.updateProject(widget.p.id, fields);
      await widget.reload();
    } on StudioException catch (e) {
      if (mounted) showStudioError(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    return Container(
      decoration: studioPanel(),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Sound & picture', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(height: 12),
        Row(children: [
          const Icon(Icons.music_note_outlined, color: AppColors.secondary, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(p.hasMusic ? (p.musicName ?? 'Background music') : 'No background music',
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: p.hasMusic ? AppColors.textPrimary : AppColors.textMuted)),
          ),
          if (_uploading)
            const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
          else ...[
            TextButton(onPressed: _pickMusic, child: Text(p.hasMusic ? 'Change' : 'Add music')),
            if (p.hasMusic)
              IconButton(
                tooltip: 'Remove music',
                onPressed: () async {
                  await CreatorStudioService.removeMusic(p.id);
                  await widget.reload();
                },
                icon: const Icon(Icons.close, size: 18, color: AppColors.textMuted),
              ),
          ],
        ]),
        if (p.hasMusic)
          Row(children: [
            const SizedBox(width: 30),
            const Text('Volume', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
            Expanded(
              child: Slider(
                value: _volume,
                min: 0.05,
                max: 0.8,
                onChanged: (v) => setState(() => _volume = v),
                onChangeEnd: (v) => _save({'music_volume': double.parse(v.toStringAsFixed(2))}),
              ),
            ),
            Text('${(_volume * 100).round()}%', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
          ]),
        const Divider(height: 24, color: StudioColors.panelBorder),
        const Text('Picture quality', style: TextStyle(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: 'standard', label: Text('Standard')),
            ButtonSegment(value: 'high', label: Text('High (sharper)')),
          ],
          selected: {p.imageQuality},
          onSelectionChanged: (v) => _save({'image_quality': v.first}),
        ),
        const SizedBox(height: 6),
        const Text('High makes new images at 2K: sharper on big screens, about 50% more per image. '
            'Images you already made keep their quality.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.35)),
        const SizedBox(height: 4),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: p.captions,
          onChanged: (v) => _save({'captions': v}),
          title: const Text('Burn in captions', style: TextStyle(fontSize: 14)),
        ),
      ]),
    );
  }
}


/// What the writers' room planned before writing, so the creator can see
/// how their idea was developed.
class _StoryPlanCard extends StatelessWidget {
  final Map<String, dynamic> plan;
  const _StoryPlanCard(this.plan);

  String _s(Object? v) => (v ?? '').toString().trim();

  @override
  Widget build(BuildContext context) {
    final chars = ((plan['characters'] as List?) ?? []).whereType<Map>().toList();
    final fixes = ((plan['fixes'] as List?) ?? []).map((e) => e.toString()).where((e) => e.trim().isNotEmpty).toList();
    final threads = ((plan['open_threads'] as List?) ?? []).map((e) => e.toString()).toList();
    Widget row(String label, String value) => value.isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(value, style: const TextStyle(fontSize: 13, height: 1.4)),
            ]),
          );
    return Container(
      decoration: studioPanel(),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          leading: const Icon(Icons.auto_stories_outlined, color: AppColors.secondary),
          title: const Text('Story plan', style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(_s(plan['logline']), maxLines: 2, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            row('Opening hook', _s(plan['opening_hook'])),
            row('Ending hook', _s(plan['ending_hook'])),
            row('What makes it different', _s(plan['premise_twist'])),
            row('Conflict', _s(plan['central_conflict'])),
            row('What\'s at stake', _s(plan['stakes'])),
            if (chars.isNotEmpty) ...[
              const Text('Characters', style: TextStyle(fontSize: 11.5, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              for (final c in chars)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '${_s(c['name'])} (${_s(c['age'])}): wants ${_s(c['want'])}'
                    '${_s(c['flaw']).isEmpty ? '' : ' · flaw: ${_s(c['flaw'])}'}'
                    '${_s(c['secret']).isEmpty ? '' : ' · secret: ${_s(c['secret'])}'}',
                    style: const TextStyle(fontSize: 12.5, height: 1.35),
                  ),
                ),
              const SizedBox(height: 4),
            ],
            row('Ending', _s(plan['ending'])),
            if (fixes.isNotEmpty) row('What the script doctor improved', fixes.map((f) => '• $f').join('\n')),
            if (threads.isNotEmpty) row('Open storylines for the next episode', threads.map((f) => '• $f').join('\n')),
          ],
        ),
      ),
    );
  }
}
