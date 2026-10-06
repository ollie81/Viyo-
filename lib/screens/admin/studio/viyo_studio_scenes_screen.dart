import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../../models/studio_character.dart';
import '../../../models/studio_scene.dart';
import '../../../services/studio_service.dart';
import '../../../theme/app_theme.dart';
import 'viyo_studio_publish_screen.dart';

const _cameraShots = ['wide', 'medium', 'close-up'];

/// Full-screen playback for a single scene's Veo clip — tapped from
/// its thumbnail badge. Same VideoPlayerController pattern as the
/// Publish screen's episode preview, just scoped to one scene instead
/// of the assembled episode.
class _ScenePreviewDialog extends StatefulWidget {
  final String videoUrl;
  final String title;

  const _ScenePreviewDialog({required this.videoUrl, required this.title});

  @override
  State<_ScenePreviewDialog> createState() => _ScenePreviewDialogState();
}

class _ScenePreviewDialogState extends State<_ScenePreviewDialog> {
  VideoPlayerController? _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
      await controller.initialize();
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() => _controller = controller..play());
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Dialog(
      backgroundColor: Colors.black,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 40),
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(28),
              child: Text(
                'Could not load video: $_error',
                style: const TextStyle(color: AppColors.danger),
                textAlign: TextAlign.center,
              ),
            )
          else if (controller != null && controller.value.isInitialized)
            AspectRatio(
              aspectRatio: 9 / 16,
              child: GestureDetector(
                onTap: () => setState(() {
                  controller.value.isPlaying ? controller.pause() : controller.play();
                }),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    VideoPlayer(controller),
                    AnimatedBuilder(
                      animation: controller,
                      builder: (_, __) => controller.value.isPlaying
                          ? const SizedBox.shrink()
                          : const Icon(Icons.play_arrow, size: 54, color: Colors.white),
                    ),
                  ],
                ),
              ),
            )
          else
            const Padding(
              padding: EdgeInsets.all(40),
              child: CircularProgressIndicator(),
            ),
          Positioned(
            top: 4,
            right: 4,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }
}

/// Viyo Studio, Phase 3: split one episode's script into scenes, then
/// generate each scene's 9:16 image (conditioned on that episode's
/// Phase 1 character/location reference images) and each dialogue
/// line's audio (using that character's Phase 2 voice).
///
/// Unlike Phase 1/2, scenes are keyed by (series_id, episode_number)
/// rather than just series_id — there's no separate "episode" entity
/// in this codebase (see studio.py's module docstring), so the admin
/// enters the episode number directly rather than picking from a list.
class ViyoStudioScenesScreen extends StatefulWidget {
  final String adminKey;
  final String seriesId;
  final String seriesTitle;

  const ViyoStudioScenesScreen({
    super.key,
    required this.adminKey,
    required this.seriesId,
    required this.seriesTitle,
  });

  @override
  State<ViyoStudioScenesScreen> createState() => _ViyoStudioScenesScreenState();
}

class _ViyoStudioScenesScreenState extends State<ViyoStudioScenesScreen> {
  final _player = AudioPlayer();
  final _episodeController = TextEditingController(text: '1');
  final _scriptController = TextEditingController();

  int _episodeNumber = 1;
  bool _loading = true;
  String? _error;
  List<StudioScene> _scenes = [];
  List<StudioCharacter> _characters = [];
  int _sessionCostCents = 0;

  bool _splitting = false;
  bool _showSplitForm = false;

  final Set<String> _generatingImages = {};
  final Set<String> _generatingVideo = {};
  final Set<String> _generatingAudio = {};
  final Set<String> _savingScene = {};
  final Set<String> _savingLine = {};

  @override
  void initState() {
    super.initState();
    _loadScenes();
    _loadCast();
  }

  /// The series' saved cast, so a dialogue line Viyo Studio couldn't
  /// match to a character automatically can offer a pick-list instead
  /// of just failing when audio generation is attempted.
  Future<void> _loadCast() async {
    try {
      final cast = await StudioService.getCast(widget.adminKey, widget.seriesId);
      if (!mounted) return;
      setState(() => _characters = cast.characters);
    } catch (_) {
      // Non-fatal — the dropdown fallback just won't have options yet;
      // the rest of the screen still works.
    }
  }

  @override
  void dispose() {
    _player.dispose();
    _episodeController.dispose();
    _scriptController.dispose();
    super.dispose();
  }

  Future<void> _loadScenes() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await StudioService.getScenes(widget.adminKey, widget.seriesId, _episodeNumber);
      if (!mounted) return;
      setState(() {
        _scenes = result.scenes;
        _showSplitForm = result.scenes.isEmpty;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _changeEpisode() {
    final n = int.tryParse(_episodeController.text.trim());
    if (n == null || n < 1) return;
    setState(() => _episodeNumber = n);
    _loadScenes();
  }

  Future<void> _splitScenes() async {
    final script = _scriptController.text.trim();
    if (script.isEmpty) return;
    setState(() => _splitting = true);
    try {
      final result = await StudioService.splitScenes(widget.adminKey, widget.seriesId, _episodeNumber, script);
      if (!mounted) return;
      setState(() {
        _scenes = result.scenes;
        _sessionCostCents += result.costUsdCents;
        _showSplitForm = false;
      });
    } catch (e) {
      if (!mounted) return;
      _showSnack(e.toString().replaceFirst(RegExp(r'^Exception:\s*'), ''));
    } finally {
      if (mounted) setState(() => _splitting = false);
    }
  }

  Future<void> _saveSceneEdit(int index) async {
    final scene = _scenes[index];
    setState(() => _savingScene.add(scene.id));
    try {
      final updated = await StudioService.editScene(
        widget.adminKey,
        scene.id,
        visualDescription: scene.visualDescription,
        cameraShot: scene.cameraShot,
        locationName: scene.locationName,
      );
      if (!mounted) return;
      setState(() => _scenes[index] = updated.copyWith(lines: scene.lines));
      _showSnack('Scene ${index + 1} saved.');
    } catch (e) {
      if (!mounted) return;
      _showSnack(e.toString().replaceFirst(RegExp(r'^Exception:\s*'), ''));
    } finally {
      if (mounted) setState(() => _savingScene.remove(scene.id));
    }
  }

  Future<void> _generateSceneImage(int index) async {
    final scene = _scenes[index];
    setState(() => _generatingImages.add(scene.id));
    try {
      final result = await StudioService.generateSceneImage(widget.adminKey, scene.id);
      if (!mounted) return;
      setState(() {
        _scenes[index] = scene.copyWith(imageUrl: result.imageUrl);
        _sessionCostCents += result.costUsdCents;
      });
    } catch (e) {
      if (!mounted) return;
      _showSnack(e.toString().replaceFirst(RegExp(r'^Exception:\s*'), ''));
    } finally {
      if (mounted) setState(() => _generatingImages.remove(scene.id));
    }
  }

  /// Veo costs real money per second (unlike every other Studio call,
  /// which is a flat cent or two) and takes minutes rather than
  /// seconds, so this always confirms the exact cost and duration
  /// first instead of generating on a single tap like the image/audio
  /// buttons do.
  Future<void> _confirmAndGenerateSceneVideo(int index) async {
    final scene = _scenes[index];
    if (scene.imageUrl == null) {
      _showSnack('Generate this scene\'s image first — Veo needs it as a starting frame.');
      return;
    }
    final duration = await showDialog<int>(
      context: context,
      builder: (ctx) {
        var selected = 8;
        return StatefulBuilder(
          builder: (ctx, setState) => AlertDialog(
            backgroundColor: AppColors.surface,
            title: const Text('Generate real video (Veo)'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Animates this scene\'s image into a real video clip instead of the usual zoom/pan. '
                  'This can take a few minutes and costs real money, unlike everything else in Studio.',
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 14),
                const Text('Clip length', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: [4, 6, 8].map((d) {
                    final isSelected = d == selected;
                    return ChoiceChip(
                      label: Text('${d}s  ·  \$${(d * 0.05).toStringAsFixed(2)}'),
                      selected: isSelected,
                      onSelected: (_) => setState(() => selected = d),
                      selectedColor: AppColors.primary.withOpacity(0.25),
                      labelStyle: TextStyle(color: isSelected ? AppColors.primary : Colors.white, fontSize: 12.5),
                    );
                  }).toList(),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, selected),
                child: const Text('Generate'),
              ),
            ],
          ),
        );
      },
    );
    if (duration == null) return;

    setState(() => _generatingVideo.add(scene.id));
    try {
      final result = await StudioService.generateSceneVideo(widget.adminKey, scene.id, durationSeconds: duration);
      if (!mounted) return;
      setState(() {
        _scenes[index] = scene.copyWith(videoUrl: result.videoUrl);
        _sessionCostCents += result.costUsdCents;
      });
      _showSnack('Scene ${index + 1} now has a real video clip.');
    } catch (e) {
      if (!mounted) return;
      _showSnack(e.toString().replaceFirst(RegExp(r'^Exception:\s*'), ''));
    } finally {
      if (mounted) setState(() => _generatingVideo.remove(scene.id));
    }
  }

  Future<void> _saveLineEdit(int sceneIndex, int lineIndex) async {
    final line = _scenes[sceneIndex].lines[lineIndex];
    setState(() => _savingLine.add(line.id));
    try {
      final updated = await StudioService.editLine(widget.adminKey, line.id, text: line.text);
      if (!mounted) return;
      setState(() => _scenes[sceneIndex] = _scenes[sceneIndex].withLineAt(lineIndex, updated));
    } catch (e) {
      if (!mounted) return;
      _showSnack(e.toString().replaceFirst(RegExp(r'^Exception:\s*'), ''));
    } finally {
      if (mounted) setState(() => _savingLine.remove(line.id));
    }
  }

  /// The "characters present" chip for a scene is a snapshot taken at
  /// split time — unlike a dialogue line's own character_id, nothing
  /// re-matches it later, so a scene split before the name matcher got
  /// smarter (or one the matcher is still ambiguous about) keeps
  /// showing "unmatched" forever unless fixed by hand. Tapping an
  /// unmatched chip opens this picker to do that.
  Future<void> _pickCharacterForScene(int sceneIndex, int charIndex) async {
    if (_characters.isEmpty) {
      _showSnack('No cast loaded yet — try again in a moment.');
      return;
    }
    final picked = await showModalBottomSheet<StudioCharacter>(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: _characters
              .map((c) => ListTile(
                    title: Text(c.name, style: const TextStyle(color: Colors.white)),
                    onTap: () => Navigator.pop(ctx, c),
                  ))
              .toList(),
        ),
      ),
    );
    if (picked == null) return;
    await _assignSceneCharacter(sceneIndex, charIndex, picked);
  }

  Future<void> _assignSceneCharacter(int sceneIndex, int charIndex, StudioCharacter character) async {
    final scene = _scenes[sceneIndex];
    final updatedCharacters = List<StudioSceneCharacterRef>.from(scene.characters);
    updatedCharacters[charIndex] = updatedCharacters[charIndex].copyWith(characterId: character.id);
    setState(() => _savingScene.add(scene.id));
    try {
      final updated = await StudioService.editScene(widget.adminKey, scene.id, characters: updatedCharacters);
      if (!mounted) return;
      setState(() => _scenes[sceneIndex] = updated.copyWith(lines: scene.lines));
    } catch (e) {
      if (!mounted) return;
      _showSnack(e.toString().replaceFirst(RegExp(r'^Exception:\s*'), ''));
    } finally {
      if (mounted) setState(() => _savingScene.remove(scene.id));
    }
  }

  /// Assigns [character] to a line Viyo Studio couldn't match on its
  /// own — the dropdown fallback for when the script's speaker name
  /// doesn't resolve to anyone in the cast, instead of only finding
  /// out when "Generate audio" fails with an error.
  Future<void> _assignLineCharacter(int sceneIndex, int lineIndex, StudioCharacter character) async {
    final line = _scenes[sceneIndex].lines[lineIndex];
    setState(() => _savingLine.add(line.id));
    try {
      final updated = await StudioService.editLine(
        widget.adminKey,
        line.id,
        characterId: character.id,
        characterName: character.name,
      );
      if (!mounted) return;
      setState(() => _scenes[sceneIndex] = _scenes[sceneIndex].withLineAt(lineIndex, updated));
    } catch (e) {
      if (!mounted) return;
      _showSnack(e.toString().replaceFirst(RegExp(r'^Exception:\s*'), ''));
    } finally {
      if (mounted) setState(() => _savingLine.remove(line.id));
    }
  }

  Future<void> _generateLineAudio(int sceneIndex, int lineIndex) async {
    final line = _scenes[sceneIndex].lines[lineIndex];
    setState(() => _generatingAudio.add(line.id));
    try {
      final result = await StudioService.generateLineAudio(widget.adminKey, line.id);
      if (!mounted) return;
      setState(() {
        _scenes[sceneIndex] = _scenes[sceneIndex].withLineAt(lineIndex, line.copyWith(audioUrl: result.audioUrl));
        _sessionCostCents += result.costUsdCents;
      });
    } catch (e) {
      if (!mounted) return;
      _showSnack(e.toString().replaceFirst(RegExp(r'^Exception:\s*'), ''));
    } finally {
      if (mounted) setState(() => _generatingAudio.remove(line.id));
    }
  }

  Future<void> _playAudio(String url) async {
    await _player.stop();
    await _player.play(UrlSource(url));
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: Text('Scenes · ${widget.seriesTitle}', overflow: TextOverflow.ellipsis),
        actions: [
          if (_scenes.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.publish_outlined),
              tooltip: 'Continue to Publish',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ViyoStudioPublishScreen(
                    adminKey: widget.adminKey,
                    seriesId: widget.seriesId,
                    seriesTitle: widget.seriesTitle,
                    episodeNumber: _episodeNumber,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _errorState()
              : _content(),
    );
  }

  Widget _errorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: AppColors.danger), textAlign: TextAlign.center),
            const SizedBox(height: 14),
            ElevatedButton(onPressed: _loadScenes, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }

  Widget _content() {
    return RefreshIndicator(
      onRefresh: _loadScenes,
      color: AppColors.primary,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _episodeHeader(),
          const SizedBox(height: 16),
          if (_showSplitForm || _scenes.isEmpty) _splitForm(),
          if (_scenes.isNotEmpty) ...[
            if (_showSplitForm) const SizedBox(height: 16),
            ..._scenes.asMap().entries.map(
                  (e) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _sceneCard(e.key, e.value),
                  ),
                ),
            if (!_showSplitForm)
              Center(
                child: TextButton(
                  onPressed: () => setState(() => _showSplitForm = true),
                  child: const Text('Re-split from script'),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _episodeHeader() {
    final sessionCost = (_sessionCostCents / 100).toStringAsFixed(2);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: AppTheme.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Episode #', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              const SizedBox(width: 10),
              SizedBox(
                width: 64,
                child: TextField(
                  controller: _episodeController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.all(8)),
                  onSubmitted: (_) => _changeEpisode(),
                ),
              ),
              const SizedBox(width: 10),
              TextButton(onPressed: _changeEpisode, child: const Text('Load')),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'This session: \$$sessionCost',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
          ),
        ],
      ),
    );
  }

  Widget _splitForm() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Paste episode $_episodeNumber\'s script',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          if (_scenes.isNotEmpty) ...[
            const SizedBox(height: 6),
            const Text(
              'Re-splitting replaces this episode\'s scenes — any images or audio already '
              'generated for them will be lost.',
              style: TextStyle(color: AppColors.coin, fontSize: 12),
            ),
          ],
          const SizedBox(height: 10),
          TextField(
            controller: _scriptController,
            maxLines: 10,
            minLines: 6,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: const InputDecoration(hintText: 'Paste this episode\'s script here...'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (_scenes.isNotEmpty)
                TextButton(
                  onPressed: _splitting ? null : () => setState(() => _showSplitForm = false),
                  child: const Text('Cancel'),
                ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: _splitting ? null : _splitScenes,
                icon: _splitting
                    ? const SizedBox(
                        width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.movie_filter_outlined, size: 18),
                label: Text(_splitting ? 'Splitting...' : 'Split into Scenes'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sceneCard(int index, StudioScene scene) {
    final imageBusy = _generatingImages.contains(scene.id);
    final videoBusy = _generatingVideo.contains(scene.id);
    final savingScene = _savingScene.contains(scene.id);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sceneImage(
                scene.imageUrl,
                busy: imageBusy,
                onGenerate: () => _generateSceneImage(index),
                hasVideo: scene.videoUrl != null,
                videoBusy: videoBusy,
                onGenerateVideo: () => _confirmAndGenerateSceneVideo(index),
                onPlayVideo: scene.videoUrl == null
                    ? null
                    : () => showDialog(
                          context: context,
                          builder: (_) => _ScenePreviewDialog(
                            videoUrl: scene.videoUrl!,
                            title: 'Scene ${index + 1}',
                          ),
                        ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('Scene ${index + 1}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                        const Spacer(),
                        DropdownButton<String>(
                          value: scene.cameraShot,
                          dropdownColor: AppColors.surface,
                          underline: const SizedBox.shrink(),
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                          items: _cameraShots
                              .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                              .toList(),
                          onChanged: (v) => v == null
                              ? null
                              : setState(() => _scenes[index] = scene.copyWith(cameraShot: v)),
                        ),
                      ],
                    ),
                    _compactField(
                      'Location',
                      scene.locationName,
                      (v) => setState(() => _scenes[index] = scene.copyWith(locationName: v)),
                    ),
                    _compactField(
                      'What happens',
                      scene.visualDescription,
                      (v) => setState(() => _scenes[index] = scene.copyWith(visualDescription: v)),
                      maxLines: 3,
                    ),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: scene.characters.asMap().entries.map((entry) {
                        final c = entry.value;
                        final unmatched = c.characterId == null;
                        final chip = Chip(
                          label: Text(
                            unmatched ? '${c.name} ?' : c.name,
                            style: const TextStyle(fontSize: 11),
                          ),
                          backgroundColor: unmatched ? AppColors.coin.withOpacity(0.15) : AppColors.background,
                          side: BorderSide(color: unmatched ? AppColors.coin : AppColors.surfaceBorder),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        );
                        if (!unmatched) return chip;
                        return GestureDetector(
                          onTap: () => _pickCharacterForScene(index, entry.key),
                          child: chip,
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: savingScene ? null : () => _saveSceneEdit(index),
                        child: savingScene
                            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Save', style: TextStyle(fontSize: 12)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 18, color: AppColors.surfaceBorder),
          ...scene.lines.asMap().entries.map((e) => _lineRow(index, e.key, e.value)),
        ],
      ),
    );
  }

  Widget _sceneImage(
    String? url, {
    required bool busy,
    required VoidCallback onGenerate,
    bool hasVideo = false,
    required bool videoBusy,
    required VoidCallback onGenerateVideo,
    VoidCallback? onPlayVideo,
  }) {
    const width = 84.0;
    const height = 149.0;
    return Column(
      children: [
        GestureDetector(
          onTap: onPlayVideo,
          child: Stack(
            children: [
              Container(
                width: width,
                height: height,
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: hasVideo ? AppColors.primary : AppColors.surfaceBorder),
                  image: url != null ? DecorationImage(image: NetworkImage(url), fit: BoxFit.cover) : null,
                ),
                child: url == null ? const Icon(Icons.image_outlined, color: AppColors.textMuted, size: 22) : null,
              ),
              if (hasVideo) ...[
                Positioned(
                  top: 4,
                  right: 4,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                    child: const Icon(Icons.videocam, size: 11, color: Colors.black),
                  ),
                ),
                Container(
                  width: width,
                  height: height,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.play_circle_fill, size: 28, color: Colors.white),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: width,
          child: busy
              ? const Padding(
                  padding: EdgeInsets.all(6),
                  child: Center(child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))),
                )
              : TextButton(
                  onPressed: onGenerate,
                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4)),
                  child: Text(url == null ? 'Generate' : 'Redo', style: const TextStyle(fontSize: 11)),
                ),
        ),
        SizedBox(
          width: width,
          child: videoBusy
              ? const Padding(
                  padding: EdgeInsets.all(6),
                  child: Center(child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))),
                )
              : TextButton(
                  onPressed: onGenerateVideo,
                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4)),
                  child: Text(
                    hasVideo ? 'Redo video' : 'Real video',
                    style: const TextStyle(fontSize: 11, color: AppColors.primary),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _compactField(String label, String value, ValueChanged<String> onChanged, {int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 2),
      child: TextFormField(
        initialValue: value,
        maxLines: maxLines,
        style: const TextStyle(color: Colors.white, fontSize: 12.5),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontSize: 11),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        ),
        onChanged: onChanged,
      ),
    );
  }

  /// Inline fallback for a dialogue line Viyo Studio couldn't match to
  /// a cast member on its own — picking a character here saves it right
  /// away, same as the error it replaces would have told the admin to
  /// do manually via Edit.
  Widget _characterPicker(int sceneIndex, int lineIndex, StudioSceneLine line) {
    final savingLine = _savingLine.contains(line.id);
    return DropdownButton<String>(
      isExpanded: true,
      value: null,
      hint: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.warning_amber_rounded, size: 13, color: AppColors.coin),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              line.characterName.isEmpty ? 'Pick character' : line.characterName,
              style: const TextStyle(fontSize: 11, color: AppColors.coin),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      underline: const SizedBox.shrink(),
      dropdownColor: AppColors.surface,
      icon: savingLine
          ? const Padding(
              padding: EdgeInsets.only(left: 2),
              child: SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          : const Icon(Icons.arrow_drop_down, size: 16, color: AppColors.textMuted),
      items: _characters
          .where((c) => c.id != null)
          .map((c) => DropdownMenuItem(
                value: c.id,
                child: Text(c.name, style: const TextStyle(fontSize: 12, color: Colors.white)),
              ))
          .toList(),
      onChanged: savingLine
          ? null
          : (id) {
              final character = _characters.firstWhere((c) => c.id == id);
              _assignLineCharacter(sceneIndex, lineIndex, character);
            },
    );
  }

  Widget _lineRow(int sceneIndex, int lineIndex, StudioSceneLine line) {
    final audioBusy = _generatingAudio.contains(line.id);
    final savingLine = _savingLine.contains(line.id);
    final hasAudio = line.audioUrl != null;
    final unmatched = line.characterId == null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: unmatched
                  ? _characterPicker(sceneIndex, lineIndex, line)
                  : Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        line.characterName,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11.5),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
            ),
          ),
          Expanded(
            child: TextFormField(
              initialValue: line.text,
              maxLines: null,
              style: const TextStyle(color: Colors.white, fontSize: 12.5),
              decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
              onChanged: (v) => setState(
                () => _scenes[sceneIndex] = _scenes[sceneIndex].withLineAt(lineIndex, line.copyWith(text: v)),
              ),
            ),
          ),
          SizedBox(
            width: 32,
            child: savingLine
                ? const Padding(padding: EdgeInsets.all(6), child: CircularProgressIndicator(strokeWidth: 2))
                : IconButton(
                    icon: const Icon(Icons.save_outlined, size: 18),
                    onPressed: () => _saveLineEdit(sceneIndex, lineIndex),
                    tooltip: 'Save line',
                  ),
          ),
          SizedBox(
            width: 32,
            child: audioBusy
                ? const Padding(padding: EdgeInsets.all(6), child: CircularProgressIndicator(strokeWidth: 2))
                : IconButton(
                    icon: Icon(hasAudio ? Icons.replay_circle_filled_outlined : Icons.graphic_eq, size: 18),
                    color: unmatched ? AppColors.textMuted : AppColors.primary,
                    onPressed: unmatched ? null : () => _generateLineAudio(sceneIndex, lineIndex),
                    tooltip: unmatched
                        ? 'Pick a character above first'
                        : (hasAudio ? 'Regenerate audio' : 'Generate audio'),
                  ),
          ),
          if (hasAudio)
            SizedBox(
              width: 32,
              child: IconButton(
                icon: const Icon(Icons.play_circle_outline, size: 18),
                onPressed: () => _playAudio(line.audioUrl!),
                tooltip: 'Play',
              ),
            ),
        ],
      ),
    );
  }
}
