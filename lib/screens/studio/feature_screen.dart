import 'package:flutter/material.dart';

import '../../services/creator_studio_service.dart';
import '../../theme/app_theme.dart';
import 'studio_project_screen.dart';
import 'studio_widgets.dart';

/// A feature film: its parts in order (each made like one production), what each still costs, which are rendered,
/// and joining them into one movie.
class FeatureScreen extends StatefulWidget {
  final String featureId;
  final Future<Map<String, dynamic>> Function(String id)? load;
  final Future<bool> Function(BuildContext context, String masterId)? join;
  final void Function(BuildContext context, String projectId)? openPart;
  const FeatureScreen({super.key, required this.featureId, this.load, this.join, this.openPart});

  @override
  State<FeatureScreen> createState() => _FeatureScreenState();
}

class _FeatureScreenState extends State<FeatureScreen> {
  Map<String, dynamic>? d;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final v = await (widget.load ?? CreatorStudioService.feature)(widget.featureId);
      if (mounted) setState(() => d = v);
    } on StudioException catch (e) {
      if (mounted) showStudioError(context, e.message);
    }
  }

  Future<void> _join() async {
    final masterId = '${d!['master_id']}';
    final started = widget.join != null
        ? await widget.join!(context, masterId)
        : await confirmAndRun(context, projectId: masterId, kind: 'render', title: 'Join the movie',
            extraWarning: 'The parts are joined end to end into one film. Only the joining is charged.',
            onStarted: (_) {}, onNeedCredits: () => showCreditsSheet(context));
    if (started && mounted) {
      showStudioInfo(context, 'Joining the movie. It appears here when it\'s ready.');
      _load();
    }
  }

  void _open(String projectId) {
    if (widget.openPart != null) return widget.openPart!(context, projectId);
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => StudioProjectScreen(projectId: projectId)))
        .then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    final v = d;
    return Scaffold(
      appBar: AppBar(title: Text(v == null ? 'Feature film' : '${v['title']}')),
      body: v == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.all(16), children: _body(v)),
            ),
    );
  }

  List<Widget> _body(Map<String, dynamic> v) {
    final parts = ((v['parts'] as List?) ?? const []).cast<Map>();
    final film = v['film'] as Map?;
    final missing = ((v['missing'] as List?) ?? const []).join(', ');
    final done = parts.where((p) => p['rendered'] == true).length;
    return [
      Text('$done of ${parts.length} parts rendered', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
      const SizedBox(height: 4),
      Text('${v['note'] ?? ''}', style: const TextStyle(fontSize: 12, color: AppColors.textMuted, height: 1.35)),
      const SizedBox(height: 4),
      Text('Still to pay for all parts: about ${creditsLabel((v['credits_to_finish'] as num?)?.toInt() ?? 0)}',
          style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
      const SizedBox(height: 10),
      for (final p in parts)
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: studioPanel(),
          child: Material(
            type: MaterialType.transparency,
            child: ListTile(
            leading: CircleAvatar(radius: 14, child: Text('${p['part']}', style: const TextStyle(fontSize: 12))),
            title: Text('${p['title']}', style: const TextStyle(fontSize: 13.5)),
            subtitle: Text(
                p['rendered'] == true
                    ? 'Rendered · ${((p['seconds'] as num?) ?? 0).round()} s'
                    : 'Not rendered yet · about ${creditsLabel((p['credits_to_finish'] as num?)?.toInt() ?? 0)} to finish',
                style: TextStyle(fontSize: 12, color: p['rendered'] == true ? AppColors.success : AppColors.textMuted)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _open('${p['project_id']}'),
            ),
          ),
        ),
      const SizedBox(height: 8),
      if (film != null)
        Container(
          padding: const EdgeInsets.all(12),
          decoration: studioPanel(),
          child: Row(children: [
            const Icon(Icons.movie, color: AppColors.success),
            const SizedBox(width: 8),
            Expanded(
                child: Text('The movie is joined: version ${film['version']}, '
                    '${(((film['duration_seconds'] as num?) ?? 0) / 60).toStringAsFixed(1)} minutes. Open it from the '
                    'movie\'s production to watch, download or publish.')),
          ]),
        ),
      const SizedBox(height: 8),
      FilledButton.icon(
        onPressed: v['ready_to_join'] == true ? _join : null,
        icon: const Icon(Icons.merge_type, size: 18),
        label: Text(film != null ? 'Join again' : 'Join the movie'),
      ),
      if (v['ready_to_join'] != true && missing.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('Render part${missing.contains(',') ? 's' : ''} $missing first.',
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
        ),
      if (film != null)
        TextButton(onPressed: () => _open('${v['master_id']}'), child: const Text('Open the movie\'s production')),
    ];
  }
}
