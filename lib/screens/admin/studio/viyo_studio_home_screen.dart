import 'package:flutter/material.dart';
import '../../../models/series.dart';
import '../../../models/studio_episode_status.dart';
import '../../../services/series_service.dart';
import '../../../services/studio_service.dart';
import '../../../theme/app_theme.dart';
import 'drama_details_dialog.dart';
import 'viyo_studio_scenes_screen.dart';
import 'viyo_studio_screen.dart';
import 'viyo_studio_voices_screen.dart';

/// Viyo Studio's entry point — shows every series with where Studio
/// work on it stands (cast cast? voices assigned? scenes split?
/// published?) so the admin can jump back into the right step instead
/// of re-pasting a script to find out, and so work in progress is
/// never just "somewhere, who knows how far along."
class ViyoStudioHomeScreen extends StatefulWidget {
  const ViyoStudioHomeScreen({super.key});

  @override
  State<ViyoStudioHomeScreen> createState() => _ViyoStudioHomeScreenState();
}

class _SeriesStudioSummary {
  final Series series;
  final int characterCount;
  final int locationCount;
  final int voicedCount;
  final List<StudioEpisodeStatus> episodes;

  _SeriesStudioSummary({
    required this.series,
    required this.characterCount,
    required this.locationCount,
    required this.voicedCount,
    required this.episodes,
  });

  bool get hasCast => characterCount > 0;
  bool get allVoiced => hasCast && voicedCount == characterCount;
}

class _ViyoStudioHomeScreenState extends State<ViyoStudioHomeScreen> {
  final _keyController = TextEditingController();
  String? _adminKey;
  String? _unlockError;

  bool _loading = false;
  String? _error;
  List<_SeriesStudioSummary> _summaries = [];

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    final key = _keyController.text.trim();
    if (key.isEmpty) return;
    setState(() {
      _adminKey = key;
      _unlockError = null;
    });
    await _load();
  }

  Future<void> _load() async {
    final adminKey = _adminKey;
    if (adminKey == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final series = await SeriesService.getAllSeries(sort: DramaSort.newest, limit: 100);
      final summaries = await Future.wait(series.map((s) async {
        try {
          final results = await Future.wait([
            StudioService.getCast(adminKey, s.id),
            StudioService.getEpisodeStatuses(adminKey, s.id),
          ]);
          final cast = results[0] as StudioCastResult;
          final episodes = results[1] as List<StudioEpisodeStatus>;
          final voiced = cast.characters.where((c) => (c.voiceId ?? '').isNotEmpty).length;
          return _SeriesStudioSummary(
            series: s,
            characterCount: cast.characters.length,
            locationCount: cast.locations.length,
            voicedCount: voiced,
            episodes: episodes,
          );
        } catch (_) {
          // One series failing to load its Studio status shouldn't
          // block the whole home screen — show it as "not started".
          return _SeriesStudioSummary(
            series: s,
            characterCount: 0,
            locationCount: 0,
            voicedCount: 0,
            episodes: const [],
          );
        }
      }));
      if (!mounted) return;
      setState(() => _summaries = summaries);
    } catch (e) {
      if (!mounted) return;
      final message = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
      if (message.contains('Invalid admin key')) {
        setState(() {
          _adminKey = null;
          _unlockError = message;
        });
      } else {
        setState(() => _error = message);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _startNewScript() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => ViyoStudioScreen(adminKey: _adminKey!)))
        .then((_) => _load());
  }

  void _continueCasting(Series series) {
    Navigator.of(context)
        .push(MaterialPageRoute(
          builder: (_) => ViyoStudioScreen(adminKey: _adminKey!, preselectedSeriesId: series.id),
        ))
        .then((_) => _load());
  }

  void _continueVoices(Series series) {
    Navigator.of(context)
        .push(MaterialPageRoute(
          builder: (_) => ViyoStudioVoicesScreen(adminKey: _adminKey!, seriesId: series.id, seriesTitle: series.title),
        ))
        .then((_) => _load());
  }

  Future<void> _editDrama(Series series) async {
    final details = await showDramaDetailsDialog(
      context,
      initialTitle: series.title,
      initialGenre: series.genre,
      initialDescription: series.description,
      title: 'Edit Drama',
      confirmLabel: 'Save',
    );
    if (details == null) return;
    try {
      await StudioService.updateDramaDetails(
        _adminKey!,
        series,
        title: details.title,
        description: details.description,
        genre: details.genre,
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      final message = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save: $message')));
    }
  }

  void _continueScenes(Series series) {
    Navigator.of(context)
        .push(MaterialPageRoute(
          builder: (_) => ViyoStudioScenesScreen(adminKey: _adminKey!, seriesId: series.id, seriesTitle: series.title),
        ))
        .then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: AppColors.background, title: const Text('Viyo Studio')),
      body: _adminKey == null ? _keyPrompt() : _content(),
    );
  }

  Widget _keyPrompt() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_awesome, size: 40, color: AppColors.textMuted),
            const SizedBox(height: 16),
            TextField(
              controller: _keyController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Admin key'),
              onSubmitted: (_) => _unlock(),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(onPressed: _unlock, child: const Text('Unlock')),
            ),
            if (_unlockError != null) ...[
              const SizedBox(height: 12),
              Text(_unlockError!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _content() {
    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.primary,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _startNewScript,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('New Script'),
            ),
          ),
          const SizedBox(height: 18),
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(top: 40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 40),
              child: Center(
                child: Column(
                  children: [
                    Text(_error!, style: const TextStyle(color: AppColors.danger), textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    ElevatedButton(onPressed: _load, child: const Text('Retry')),
                  ],
                ),
              ),
            )
          else if (_summaries.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 40),
              child: Center(
                child: Text('No series yet.', style: TextStyle(color: AppColors.textMuted)),
              ),
            )
          else
            ..._summaries.map((s) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _seriesCard(s),
                )),
        ],
      ),
    );
  }

  Widget _seriesCard(_SeriesStudioSummary s) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  s.series.title,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              InkWell(
                onTap: () => _editDrama(s.series),
                borderRadius: BorderRadius.circular(16),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.edit_outlined, size: 16, color: AppColors.textMuted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _statusChip(
                label: s.hasCast ? 'Cast: ${s.characterCount} chars, ${s.locationCount} locations' : 'Cast: not started',
                done: s.hasCast,
              ),
              if (s.hasCast)
                _statusChip(label: 'Voices: ${s.voicedCount}/${s.characterCount}', done: s.allVoiced),
              if (s.episodes.isEmpty)
                _statusChip(label: 'Scenes: not started', done: false)
              else
                ...s.episodes.map((e) => _statusChip(
                      label: 'Ep ${e.episodeNumber}: ${e.published ? 'published' : (e.imagesDone && e.audioDone ? 'ready' : '${e.sceneCount} scenes')}',
                      done: e.published,
                    )),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _continueCasting(s.series),
                  child: Text(s.hasCast ? 'Edit Cast' : 'Start Casting'),
                ),
              ),
              if (s.hasCast) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _continueVoices(s.series),
                    child: const Text('Voices'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _continueScenes(s.series),
                    child: const Text('Scenes'),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusChip({required String label, required bool done}) {
    final color = done ? AppColors.success : AppColors.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(done ? Icons.check_circle : Icons.radio_button_unchecked, size: 13, color: color),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(fontSize: 11.5, color: color)),
        ],
      ),
    );
  }
}
