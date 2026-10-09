import 'package:flutter/material.dart';
import '../../../models/series.dart';
import '../../../models/studio_episode_status.dart';
import '../../../services/series_service.dart';
import '../../../services/studio_service.dart';
import '../../../services/supabase_service.dart';
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
  bool _backfillingCovers = false;

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

  /// A standalone "create a new drama" entry point, right on the home
  /// screen — previously the only way to create a new series was
  /// buried inside ViyoStudioScreen's "New Drama" button, which only
  /// appears after pasting a script and analyzing it, so there was no
  /// visible way to start a fresh drama shell without first producing
  /// a cast for something. Creates the series immediately, then opens
  /// it preselected so the admin can start casting it right away —
  /// an entirely new row, never touching any existing series' cast,
  /// scenes, or episodes.
  Future<void> _startNewDrama() async {
    final userId = SupabaseService.currentUserId;
    if (userId == null) return;
    final details = await showDramaDetailsDialog(context, title: 'New Drama', confirmLabel: 'Create');
    if (details == null) return;
    try {
      final series = await SeriesService.createSeries(
        userId: details.creatorUserId ?? userId,
        title: details.title,
        description: details.description,
        genre: details.genre,
        contentType: kContentTypeShortDrama,
        orientation: kOrientationVertical,
      );
      if (!mounted) return;
      Navigator.of(context)
          .push(MaterialPageRoute(
            builder: (_) => ViyoStudioScreen(adminKey: _adminKey!, preselectedSeriesId: series.id),
          ))
          .then((_) => _load());
    } catch (e) {
      if (!mounted) return;
      final message = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not create drama: $message')));
    }
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

  /// Removes a wrongly-published episode (wrong series, a test run,
  /// anything that shouldn't have gone out as a real drama) — the
  /// admin key lets this bypass PostService.deletePost's owner-only
  /// RLS, since a Studio-published post's owner is the series' own
  /// designated account, not whoever is holding the admin key.
  Future<void> _deleteEpisode(StudioEpisodeStatus e) async {
    final postId = e.postId;
    if (postId == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Delete episode?'),
        content: Text(
          'Removes Episode ${e.episodeNumber} from the Dramas feed and its video from Bunny. '
          'This can\'t be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await StudioService.deletePost(_adminKey!, postId);
      await _load();
    } catch (err) {
      if (!mounted) return;
      final message = err.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not delete: $message')));
    }
  }

  /// Re-compresses every series cover already in the database — see
  /// StudioService.backfillSeriesCovers's own doc comment. A one-off
  /// cleanup for covers set before that endpoint started compressing
  /// new ones automatically, so this is safe to leave as a manual
  /// button rather than something that needs to run on its own: once
  /// every old oversized cover has been caught, re-running it finds
  /// nothing left to do.
  Future<void> _backfillCovers() async {
    if (_backfillingCovers) return;
    setState(() => _backfillingCovers = true);
    try {
      final result = await StudioService.backfillSeriesCovers(_adminKey!);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          'Checked ${result.checked} covers — compressed ${result.compressed}, '
          'already small ${result.skipped}, failed ${result.failed}.',
        ),
      ));
    } catch (err) {
      if (!mounted) return;
      final message = err.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not compress covers: $message')));
    } finally {
      if (mounted) setState(() => _backfillingCovers = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: const Text('Viyo Studio'),
        actions: [
          if (_adminKey != null)
            IconButton(
              tooltip: 'Compress oversized series covers',
              icon: _backfillingCovers
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textMuted),
                    )
                  : const Icon(Icons.compress, color: AppColors.textMuted),
              onPressed: _backfillingCovers ? null : _backfillCovers,
            ),
        ],
      ),
      body: SupabaseService.isGuest ? _guestBlock() : (_adminKey == null ? _keyPrompt() : _content()),
    );
  }

  // Studio has no idea of its own who's holding the admin key — any
  // drama it publishes gets owned by whatever Supabase account is
  // currently signed in (StudioService.publishEpisode defaults the
  // post's creator to the caller's own session unless a different
  // account is explicitly picked in the New Drama dialog). An
  // anonymous guest session is disposable — it can expire or get
  // cleared with nothing recoverable — so a drama published while
  // signed in as one would be owned by an account that might not
  // exist next week. Blocking Studio entirely for a guest session
  // forces logging into (or creating) a real account first, so every
  // drama has a durable owner from the moment it's published.
  Widget _guestBlock() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 40, color: AppColors.textMuted),
            SizedBox(height: 16),
            Text(
              'Log into a real account first',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 8),
            Text(
              "You're browsing as a guest. Anything Studio publishes gets owned by whoever's "
              "signed in, and a guest session isn't durable — log in or create an account from "
              'the Profile tab, then come back to Studio.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
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
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _startNewDrama,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('New Drama'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _startNewScript,
                  icon: const Icon(Icons.auto_awesome, size: 18),
                  label: const Text('New Script'),
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              '"New Drama" creates an empty series right away — nothing existing is ever '
              'touched. "New Script" starts a blank paste-and-analyze session you assign to '
              'a series (new or existing) afterward.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 11.5),
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
                ...s.episodes.map((e) => _episodeChip(e)),
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

  Widget _episodeChip(StudioEpisodeStatus e) {
    final chip = _statusChip(
      label: 'Ep ${e.episodeNumber}: ${e.published ? 'published' : (e.imagesDone && e.audioDone ? 'ready' : '${e.sceneCount} scenes')}',
      done: e.published,
    );
    if (!e.published || e.postId == null) return chip;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        chip,
        InkWell(
          onTap: () => _deleteEpisode(e),
          borderRadius: BorderRadius.circular(12),
          child: const Padding(
            padding: EdgeInsets.only(left: 2),
            child: Icon(Icons.delete_outline, size: 15, color: AppColors.danger),
          ),
        ),
      ],
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
