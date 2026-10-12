import 'package:flutter/material.dart';
import '../../../models/series.dart';
import '../../../models/studio_character.dart';
import '../../../services/drama_creator_service.dart';
import '../../../services/studio_service.dart';
import '../../../theme/app_theme.dart';
import 'viyo_studio_scenes_screen.dart';

/// The AI-assistant-driven "New Drama" flow: a director describes a
/// one-line idea instead of pasting a finished script, and the AI
/// Drama Assistant develops it into a title, structured plot, and
/// cast — then a cinematic cover and a four-view reference sheet per
/// character — before generating episode 1's storyboard. One
/// continuous scrolling screen, sections revealed as each step
/// completes, mirroring the shape of Viyo Studio's existing phased
/// screens rather than a wizard with separate pages.
///
/// Sits ALONGSIDE the existing paste-a-script flow (ViyoStudioScreen)
/// — it does not replace "New Drama" on the home screen, which keeps
/// working exactly as it does today. This is reached from a second,
/// clearly-separate entry point.
// Matches drama_creator.py's own MAX_CHARACTERS — display only; the
// backend is the actual source of truth and enforces it server-side.
const _kMaxCharacters = 4;

class NewDramaAiScreen extends StatefulWidget {
  final String adminKey;
  final String seriesId;
  const NewDramaAiScreen({super.key, required this.adminKey, required this.seriesId});

  @override
  State<NewDramaAiScreen> createState() => _NewDramaAiScreenState();
}

class _NewDramaAiScreenState extends State<NewDramaAiScreen> {
  bool _loading = true;
  String? _loadError;

  final _ideaController = TextEditingController();
  String _genre = kDefaultDramaGenre;
  bool _generatingIdea = false;

  String _title = '';
  DramaPlot _plot = const DramaPlot();
  List<StudioCharacter> _characters = [];
  final Set<String> _castingCharacterIds = {};

  // Purely a client-side UI gate: hides further plot/character edits
  // and reveals the cover/four-view sections. The real, server-side
  // "no re-editing later" enforcement is confirmSetup() refusing to
  // run until the cover and every sheet actually exist — this
  // checkbox just starts that next phase.
  bool _storySetupLocked = false;

  bool _generatingCover = false;
  String? _coverImageUrl;
  final Set<String> _generatingViewsForCharacterId = {};

  int _episodeDurationSeconds = 30;
  // Null = default pacing (duration-driven). Set = denser/sparser than
  // the default — see DramaSetupResult.episodeSceneCount.
  int? _episodeSceneCount;
  int _pointsUsed = 0;
  bool _confirmingAndGenerating = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ideaController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final setup = await DramaCreatorService.getSetup(widget.adminKey, widget.seriesId);
      if (!mounted) return;
      setState(() {
        _title = setup.title;
        _genre = kDramaGenres.contains(setup.genre) ? setup.genre : kDefaultDramaGenre;
        _plot = setup.plot;
        _characters = setup.characters;
        _coverImageUrl = setup.coverImageUrl;
        _episodeDurationSeconds = setup.episodeDurationSeconds;
        _episodeSceneCount = setup.episodeSceneCount;
        _pointsUsed = setup.pointsUsed;
        // Resuming a drama whose story was already generated (even if
        // not yet locked/confirmed) skips straight past the idea
        // intake — there's nothing to re-ask for.
        _storySetupLocked = setup.setupConfirmed || !_plot.isEmpty;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadError = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool get _hasStory => !_plot.isEmpty && _characters.isNotEmpty;
  bool get _allPortraitsReady => _characters.isNotEmpty && _characters.every((c) => (c.portraitUrl ?? '').isNotEmpty);
  bool get _allSheetsReady => _characters.isNotEmpty && _characters.every((c) => c.hasFourViewSheet);
  bool get _readyToConfirm => _hasStory && _allPortraitsReady && _allSheetsReady && _coverImageUrl != null;

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _developIdea() async {
    final idea = _ideaController.text.trim();
    if (idea.isEmpty) return;
    setState(() => _generatingIdea = true);
    try {
      final result = await DramaCreatorService.generateIdea(widget.adminKey, widget.seriesId, ideaText: idea, genre: _genre);
      if (!mounted) return;
      setState(() {
        _title = result.title;
        _plot = result.plot;
        _characters = result.characters;
        _pointsUsed = result.pointsUsed;
      });
      await _castEveryCharacterMissingAPortrait();
    } catch (e) {
      if (!mounted) return;
      _showSnack(e.toString().replaceFirst(RegExp(r'^Exception:\s*'), ''));
    } finally {
      if (mounted) setState(() => _generatingIdea = false);
    }
  }

  /// Generates a portrait for every character that doesn't have one
  /// yet, persisting each via the exact same generateCharacterPortrait
  /// + saveCast pair the old paste-script flow already uses — nothing
  /// new on the backend for this step, pure reuse. A failure here used
  /// to just flash a snackbar and leave the character silently stuck
  /// forever (no portrait, "Confirm story & cast" permanently disabled,
  /// no way to tell why) — see _generatePortraitFor for the per-
  /// character retry this now exposes in the UI.
  Future<void> _castEveryCharacterMissingAPortrait() async {
    for (final character in List.of(_characters)) {
      if ((character.portraitUrl ?? '').isNotEmpty || character.id == null) continue;
      await _generatePortraitFor(character);
    }
  }

  /// Casts (or re-casts, after an earlier failure) a single character.
  /// Pulled out of _castEveryCharacterMissingAPortrait so a character
  /// whose portrait generation failed — the only thing that can leave
  /// "Confirm story & cast" permanently disabled with nothing visibly
  /// happening — has a real retry button instead of being stuck until
  /// the whole idea is regenerated from scratch.
  Future<void> _generatePortraitFor(StudioCharacter character) async {
    if (character.id == null) return;
    setState(() => _castingCharacterIds.add(character.id!));
    try {
      final portrait = await StudioService.generateCharacterPortrait(widget.adminKey, character);
      final updated = character.copyWith(portraitUrl: portrait.imageUrl);
      final saved = await StudioService.saveCast(widget.adminKey, widget.seriesId, characters: [updated], locations: const []);
      if (!mounted) return;
      setState(() {
        final savedChar = saved.characters.firstWhere((c) => c.id == character.id, orElse: () => updated);
        _characters = _characters.map((c) => c.id == character.id ? savedChar : c).toList();
      });
    } catch (e) {
      if (!mounted) return;
      _showSnack('Could not cast ${character.name}: ${e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '')}');
    } finally {
      if (mounted) setState(() => _castingCharacterIds.remove(character.id));
    }
  }

  Future<void> _editPlot() async {
    final controllers = {
      'premise': TextEditingController(text: _plot.premise),
      'main_conflict': TextEditingController(text: _plot.mainConflict),
      'character_motivations': TextEditingController(text: _plot.characterMotivations),
      'major_secrets': TextEditingController(text: _plot.majorSecrets),
      'emotional_turning_points': TextEditingController(text: _plot.emotionalTurningPoints),
      'episode_progression': TextEditingController(text: _plot.episodeProgression),
      'opening_hook': TextEditingController(text: _plot.openingHook),
      'cliffhanger': TextEditingController(text: _plot.cliffhanger),
    };
    const labels = {
      'premise': 'Premise',
      'main_conflict': 'Main conflict',
      'character_motivations': 'Character motivations',
      'major_secrets': 'Major secrets',
      'emotional_turning_points': 'Emotional turning points',
      'episode_progression': 'Episode progression',
      'opening_hook': 'Opening hook (what scene 1 opens on)',
      'cliffhanger': 'Cliffhanger (what the final scene ends on)',
    };
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (ctx, scrollController) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Plot', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 12),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  children: labels.entries
                      .map((e) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: TextField(
                              controller: controllers[e.key],
                              maxLines: null,
                              style: const TextStyle(color: Colors.white, fontSize: 13),
                              decoration: InputDecoration(labelText: e.value),
                            ),
                          ))
                      .toList(),
                ),
              ),
              const SizedBox(height: 8),
              ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
            ],
          ),
        ),
      ),
    );
    if (saved != true) return;
    final updated = DramaPlot(
      premise: controllers['premise']!.text,
      mainConflict: controllers['main_conflict']!.text,
      characterMotivations: controllers['character_motivations']!.text,
      majorSecrets: controllers['major_secrets']!.text,
      emotionalTurningPoints: controllers['emotional_turning_points']!.text,
      episodeProgression: controllers['episode_progression']!.text,
      openingHook: controllers['opening_hook']!.text,
      cliffhanger: controllers['cliffhanger']!.text,
    );
    try {
      final saved = await DramaCreatorService.updatePlot(widget.adminKey, widget.seriesId, updated);
      if (!mounted) return;
      setState(() => _plot = saved);
    } catch (e) {
      if (!mounted) return;
      _showSnack(e.toString().replaceFirst(RegExp(r'^Exception:\s*'), ''));
    }
  }

  Future<void> _lockStorySetup() async {
    if (!_hasStory) {
      _showSnack('Add characters and a story first.');
      return;
    }
    if (!_allPortraitsReady) {
      _showSnack('Still casting your characters — give it a moment.');
      return;
    }
    setState(() => _storySetupLocked = true);
    if (_coverImageUrl == null) await _generateCover();
    for (final c in List.of(_characters)) {
      if (!c.hasFourViewSheet) await _generateViewsFor(c);
    }
  }

  Future<void> _generateCover() async {
    setState(() => _generatingCover = true);
    try {
      final result = await DramaCreatorService.generateCover(widget.adminKey, widget.seriesId);
      if (!mounted) return;
      setState(() {
        _coverImageUrl = result.coverImageUrl;
        _pointsUsed = result.pointsUsed;
      });
    } catch (e) {
      if (!mounted) return;
      _showSnack(e.toString().replaceFirst(RegExp(r'^Exception:\s*'), ''));
    } finally {
      if (mounted) setState(() => _generatingCover = false);
    }
  }

  Future<void> _generateViewsFor(StudioCharacter character) async {
    if (character.id == null) return;
    setState(() => _generatingViewsForCharacterId.add(character.id!));
    try {
      final result = await DramaCreatorService.generateCharacterViews(widget.adminKey, character.id!);
      if (!mounted) return;
      setState(() {
        _pointsUsed = result.pointsUsed;
        _characters = _characters
            .map((c) => c.id == character.id
                ? c.copyWith(
                    frontViewUrl: result.frontViewUrl,
                    sideViewUrl: result.sideViewUrl,
                    rearViewUrl: result.rearViewUrl,
                    fourViewSheetUrl: result.fourViewSheetUrl,
                  )
                : c)
            .toList();
      });
    } catch (e) {
      if (!mounted) return;
      _showSnack('Could not build a reference sheet for ${character.name}: ${e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '')}');
    } finally {
      if (mounted) setState(() => _generatingViewsForCharacterId.remove(character.id));
    }
  }

  Future<void> _pickEpisodeDuration(int seconds) async {
    setState(() => _episodeDurationSeconds = seconds);
    try {
      await DramaCreatorService.updateEpisodeSettings(widget.adminKey, widget.seriesId, episodeDurationSeconds: seconds);
    } catch (e) {
      if (!mounted) return;
      _showSnack(e.toString().replaceFirst(RegExp(r'^Exception:\s*'), ''));
    }
  }

  /// Null picks "Auto" — back to the backend's default duration-driven
  /// pacing. A real number overrides it for a drama that wants denser
  /// or sparser scenes than that default curve would choose (e.g. many
  /// short close-up beats rather than a few longer ones). "Auto" sends
  /// 0 — the backend's clear sentinel (see update_episode_settings) —
  /// rather than skipping the call, so re-picking Auto actually clears
  /// a previously-set override instead of leaving it stale server-side.
  Future<void> _pickEpisodeSceneCount(int? count) async {
    setState(() => _episodeSceneCount = count);
    try {
      await DramaCreatorService.updateEpisodeSettings(widget.adminKey, widget.seriesId, episodeSceneCount: count ?? 0);
    } catch (e) {
      if (!mounted) return;
      _showSnack(e.toString().replaceFirst(RegExp(r'^Exception:\s*'), ''));
    }
  }

  Future<void> _confirmAndGenerateStoryboard() async {
    if (!_readyToConfirm) {
      _showSnack('Finish the cover and every character\'s reference sheet first.');
      return;
    }
    setState(() => _confirmingAndGenerating = true);
    try {
      final points = await DramaCreatorService.confirmSetup(widget.adminKey, widget.seriesId);
      if (!mounted) return;
      setState(() => _pointsUsed = points);
      await DramaCreatorService.generateStoryboard(widget.adminKey, widget.seriesId);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => ViyoStudioScenesScreen(adminKey: widget.adminKey, seriesId: widget.seriesId, seriesTitle: _title),
      ));
    } catch (e) {
      if (!mounted) return;
      _showSnack(e.toString().replaceFirst(RegExp(r'^Exception:\s*'), ''));
    } finally {
      if (mounted) setState(() => _confirmingAndGenerating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: AppColors.background, title: const Text('New Drama')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_loadError!, style: const TextStyle(color: AppColors.danger))))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  children: [
                    _assistantBubble(),
                    const SizedBox(height: 16),
                    if (!_hasStory) _ideaInputCard() else _storySetupCard(),
                    if (_storySetupLocked) ...[
                      const SizedBox(height: 20),
                      _sectionLabel('Drama cover'),
                      _coverSection(),
                      const SizedBox(height: 20),
                      _sectionLabel('${_characters.length} character four-view sheet${_characters.length == 1 ? '' : 's'}'),
                      ..._characters.map(_characterSheetTile),
                      const SizedBox(height: 20),
                      _confirmBar(),
                    ],
                  ],
                ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
      );

  Widget _assistantBubble() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const CircleAvatar(radius: 18, backgroundColor: Color(0xFFE91E8C), child: Text('AI', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800))),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: AppTheme.card(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Drma AI Assistant', style: TextStyle(color: Color(0xFFE91E8C), fontWeight: FontWeight.w800, fontSize: 13)),
                const SizedBox(height: 6),
                Text(
                  _hasStory
                      ? 'Here\'s "$_title" — review your cast and story below, then confirm when you\'re happy with it.'
                      : 'Dear Director, what kind of story would you like to create? Write down your idea and let Drma bring it to life.',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 13.5, height: 1.4),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _ideaInputCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Genre', style: TextStyle(fontSize: 11, color: AppColors.textMuted, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: kDramaGenres
                .map((g) => ChoiceChip(label: Text(g), selected: _genre == g, onSelected: (_) => setState(() => _genre = g)))
                .toList(),
          ),
          const SizedBox(height: 14),
          const Text('Your idea', style: TextStyle(fontSize: 11, color: AppColors.textMuted, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          TextField(
            controller: _ideaController,
            maxLines: 4,
            style: const TextStyle(color: Colors.white, fontSize: 13.5),
            decoration: const InputDecoration(
              hintText: 'e.g. A poor student discovers she is the missing heir to a wealthy family.',
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _generatingIdea ? null : _developIdea,
              icon: _generatingIdea
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.auto_awesome, size: 16),
              label: Text(_generatingIdea ? 'Developing your story...' : 'Develop this idea'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _storySetupCard() {
    final castingCount = _characters.length;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Story setup', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: AppColors.surfaceBorder, borderRadius: BorderRadius.circular(20)),
                child: Text(_storySetupLocked ? '2/2' : '${_allPortraitsReady ? 2 : 1}/2', style: const TextStyle(fontSize: 11)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(_title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 12),
          const Divider(color: AppColors.surfaceBorder, height: 1),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.check_circle, size: 16, color: _allPortraitsReady ? AppColors.success : AppColors.textMuted),
              const SizedBox(width: 8),
              Text('Characters', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              const Spacer(),
              Text('$castingCount added, max $_kMaxCharacters', style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
            ],
          ),
          const SizedBox(height: 10),
          ..._characters.map(_characterRow),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(Icons.check_circle, size: 16, color: AppColors.success),
              const SizedBox(width: 8),
              const Text('Plot', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              const Spacer(),
              OutlinedButton.icon(onPressed: _editPlot, icon: const Icon(Icons.search, size: 14), label: const Text('View', style: TextStyle(fontSize: 12))),
            ],
          ),
          const SizedBox(height: 6),
          Text(_plot.premise, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
          if (!_storySetupLocked) ...[
            const SizedBox(height: 16),
            const Divider(color: AppColors.surfaceBorder, height: 1),
            const SizedBox(height: 12),
            const Text('Episode length', style: TextStyle(fontSize: 11, color: AppColors.textMuted, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [30, 45, 60, 90, 120]
                  .map((d) => ChoiceChip(label: Text('${d}s'), selected: _episodeDurationSeconds == d, onSelected: (_) => _pickEpisodeDuration(d)))
                  .toList(),
            ),
            const SizedBox(height: 14),
            const Text(
              'Scene count',
              style: TextStyle(fontSize: 11, color: AppColors.textMuted, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            const Text(
              'Auto paces scenes to the length above. Override it for a denser or sparser episode — e.g. many '
              'short close-up beats instead of a few longer scenes.',
              style: TextStyle(fontSize: 10.5, color: AppColors.textMuted),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [null, 6, 8, 10, 12, 16]
                  .map((n) => ChoiceChip(
                        label: Text(n == null ? 'Auto' : '$n'),
                        selected: _episodeSceneCount == n,
                        onSelected: (_) => _pickEpisodeSceneCount(n),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _allPortraitsReady ? _lockStorySetup : null,
                icon: const Icon(Icons.check_circle_outline, size: 18),
                label: const Text('Confirm story & cast'),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _allPortraitsReady
                  ? 'No re-editing after this — reveals the cover and character sheets next.'
                  : (_castingCharacterIds.isNotEmpty
                      ? 'Still casting your characters — this unlocks once portraits finish.'
                      : 'A character above has no portrait yet — tap Retry on it, then this unlocks.'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
          ] else
            Row(
              children: const [
                Icon(Icons.check_circle, size: 18, color: AppColors.success),
                SizedBox(width: 8),
                Text('Confirmed, no re-editing later', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
              ],
            ),
        ],
      ),
    );
  }

  Widget _characterRow(StudioCharacter c) {
    final busy = c.id != null && _castingCharacterIds.contains(c.id);
    final missingPortrait = (c.portraitUrl ?? '').isEmpty;
    return Row(
      children: [
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => _openCharacterDetail(c),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: (c.portraitUrl ?? '').isNotEmpty
                        ? Image.network(c.portraitUrl!, width: 40, height: 40, fit: BoxFit.cover)
                        : Container(
                            width: 40,
                            height: 40,
                            color: AppColors.surfaceBorder,
                            child: busy
                                ? const Padding(padding: EdgeInsets.all(10), child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.person_outline, size: 18, color: AppColors.textMuted),
                          ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(c.name, style: const TextStyle(fontSize: 13.5)),
                        // The one and only symptom of a silently-failed
                        // portrait cast — without this, the character
                        // just sits there forever with nothing but a
                        // grey placeholder icon, and the admin has no
                        // way to tell that's *why* "Confirm story &
                        // cast" below stays disabled.
                        if (missingPortrait)
                          Text(
                            busy ? 'Casting…' : 'No portrait yet',
                            style: TextStyle(fontSize: 10.5, color: busy ? AppColors.textMuted : AppColors.danger),
                          ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, size: 18, color: AppColors.textMuted),
                ],
              ),
            ),
          ),
        ),
        if (missingPortrait && !busy)
          TextButton(
            onPressed: () => _generatePortraitFor(c),
            child: const Text('Retry', style: TextStyle(fontSize: 12.5)),
          ),
      ],
    );
  }

  /// Tapping a character in the cast list — the only way into their
  /// full details (age/gender/appearance/clothing/personality plus the
  /// AI-generated skin tone/face shape/eye color/hairstyle/body
  /// proportions/voice description) since the compact row above only
  /// has room for the portrait and name. Editable until story setup is
  /// locked, same cutoff the plot editor (_editPlot) and the "no
  /// re-editing later" copy already promise elsewhere on this screen —
  /// after that it's view-only, falling back to the four-view sheet
  /// section below for anything further.
  Future<void> _openCharacterDetail(StudioCharacter c) async {
    final editable = !_storySetupLocked;
    final controllers = {
      'name': TextEditingController(text: c.name),
      'age': TextEditingController(text: c.age),
      'gender': TextEditingController(text: c.gender),
      'appearance': TextEditingController(text: c.appearance),
      'clothing': TextEditingController(text: c.clothing),
      'costume_lock': TextEditingController(text: c.costumeLock),
      'personality': TextEditingController(text: c.personality),
      'skin_tone': TextEditingController(text: c.skinTone),
      'face_shape': TextEditingController(text: c.faceShape),
      'eye_color': TextEditingController(text: c.eyeColor),
      'hairstyle': TextEditingController(text: c.hairstyle),
      'body_proportions': TextEditingController(text: c.bodyProportions),
      'voice_description': TextEditingController(text: c.voiceDescription),
    };
    const labels = {
      'name': 'Name',
      'age': 'Age',
      'gender': 'Gender',
      'appearance': 'Appearance',
      'clothing': 'Clothing',
      'costume_lock': 'Costume lock (optional)',
      'personality': 'Personality',
      'skin_tone': 'Skin tone',
      'face_shape': 'Face shape',
      'eye_color': 'Eye color',
      'hairstyle': 'Hairstyle',
      'body_proportions': 'Body proportions',
      'voice_description': 'Voice description',
    };
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (ctx, scrollController) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: (c.portraitUrl ?? '').isNotEmpty
                        ? Image.network(c.portraitUrl!, width: 48, height: 48, fit: BoxFit.cover)
                        : Container(
                            width: 48,
                            height: 48,
                            color: AppColors.surfaceBorder,
                            child: const Icon(Icons.person_outline, size: 20, color: AppColors.textMuted),
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      editable ? 'Edit character' : 'Character details',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                    ),
                  ),
                ],
              ),
              if (!editable) ...[
                const SizedBox(height: 6),
                const Text(
                  'Story setup is locked — view only.',
                  style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
              ],
              const SizedBox(height: 12),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  children: labels.entries
                      .map((e) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: TextField(
                              controller: controllers[e.key],
                              enabled: editable,
                              maxLines: e.key == 'appearance' ? 2 : 1,
                              style: const TextStyle(color: Colors.white, fontSize: 13),
                              decoration: InputDecoration(labelText: e.value),
                            ),
                          ))
                      .toList(),
                ),
              ),
              const SizedBox(height: 8),
              if (editable)
                ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save'))
              else
                OutlinedButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Close')),
            ],
          ),
        ),
      ),
    );
    if (saved != true || c.id == null) return;
    final updated = c.copyWith(
      name: controllers['name']!.text,
      age: controllers['age']!.text,
      gender: controllers['gender']!.text,
      appearance: controllers['appearance']!.text,
      clothing: controllers['clothing']!.text,
      costumeLock: controllers['costume_lock']!.text,
      personality: controllers['personality']!.text,
      skinTone: controllers['skin_tone']!.text,
      faceShape: controllers['face_shape']!.text,
      eyeColor: controllers['eye_color']!.text,
      hairstyle: controllers['hairstyle']!.text,
      bodyProportions: controllers['body_proportions']!.text,
      voiceDescription: controllers['voice_description']!.text,
    );
    try {
      final result = await StudioService.saveCast(widget.adminKey, widget.seriesId, characters: [updated], locations: const []);
      if (!mounted) return;
      setState(() {
        final savedChar = result.characters.firstWhere((sc) => sc.id == c.id, orElse: () => updated);
        _characters = _characters.map((existing) => existing.id == c.id ? savedChar : existing).toList();
      });
    } catch (e) {
      if (!mounted) return;
      _showSnack(e.toString().replaceFirst(RegExp(r'^Exception:\s*'), ''));
    }
  }

  Widget _coverSection() {
    return Column(
      children: [
        Container(
          decoration: AppTheme.card(),
          clipBehavior: Clip.antiAlias,
          child: AspectRatio(
            aspectRatio: 9 / 16,
            child: _generatingCover
                ? const Center(child: CircularProgressIndicator())
                : _coverImageUrl == null
                    ? const Center(child: Text('No cover yet', style: TextStyle(color: AppColors.textMuted)))
                    : Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.network(_coverImageUrl!, fit: BoxFit.cover),
                          Positioned(
                            top: 24,
                            left: 16,
                            right: 16,
                            child: Text(
                              _title,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                                fontFamily: 'serif',
                                shadows: [Shadow(color: Colors.black87, blurRadius: 10)],
                              ),
                            ),
                          ),
                        ],
                      ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(onPressed: _generatingCover ? null : _generateCover, child: const Text('Regenerate cover image')),
        ),
      ],
    );
  }

  Widget _characterSheetTile(StudioCharacter c) {
    final busy = c.id != null && _generatingViewsForCharacterId.contains(c.id);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(c.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 8),
          AspectRatio(
            aspectRatio: 16 / 7,
            child: Container(
              decoration: AppTheme.card(),
              clipBehavior: Clip.antiAlias,
              child: c.hasFourViewSheet
                  ? Image.network(c.fourViewSheetUrl!, fit: BoxFit.cover)
                  : Center(
                      child: busy
                          ? const CircularProgressIndicator()
                          : TextButton.icon(
                              onPressed: () => _generateViewsFor(c),
                              icon: const Icon(Icons.auto_awesome, size: 16),
                              label: const Text('Generate reference sheet'),
                            ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _confirmBar() {
    return Column(
      children: [
        Row(
          children: [
            const Icon(Icons.auto_awesome, size: 14, color: AppColors.secondary),
            const SizedBox(width: 6),
            Text('Uses $_pointsUsed points', style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          'Confirming begins generating the full episode-1 storyboard from your story above.',
          style: TextStyle(fontSize: 11, color: AppColors.textMuted),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _readyToConfirm && !_confirmingAndGenerating ? _confirmAndGenerateStoryboard : null,
            child: _confirmingAndGenerating
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Confirm & generate storyboard scenes'),
          ),
        ),
      ],
    );
  }
}
