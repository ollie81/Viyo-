import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import '../../../models/studio_scene.dart';
import '../../../services/studio_service.dart';
import '../../../theme/app_theme.dart';

const _cameraShots = ['wide', 'medium', 'close-up'];

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
  int _sessionCostCents = 0;

  bool _splitting = false;
  bool _showSplitForm = false;

  final Set<String> _generatingImages = {};
  final Set<String> _generatingAudio = {};
  final Set<String> _savingScene = {};
  final Set<String> _savingLine = {};

  @override
  void initState() {
    super.initState();
    _loadScenes();
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
              _sceneImage(scene.imageUrl, busy: imageBusy, onGenerate: () => _generateSceneImage(index)),
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
                      children: scene.characters
                          .map(
                            (c) => Chip(
                              label: Text(c.name, style: const TextStyle(fontSize: 11)),
                              backgroundColor: c.characterId == null ? AppColors.coin.withOpacity(0.15) : AppColors.background,
                              side: BorderSide(color: c.characterId == null ? AppColors.coin : AppColors.surfaceBorder),
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          )
                          .toList(),
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

  Widget _sceneImage(String? url, {required bool busy, required VoidCallback onGenerate}) {
    const width = 84.0;
    const height = 149.0;
    return Column(
      children: [
        Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.surfaceBorder),
            image: url != null ? DecorationImage(image: NetworkImage(url), fit: BoxFit.cover) : null,
          ),
          child: url == null ? const Icon(Icons.image_outlined, color: AppColors.textMuted, size: 22) : null,
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

  Widget _lineRow(int sceneIndex, int lineIndex, StudioSceneLine line) {
    final audioBusy = _generatingAudio.contains(line.id);
    final savingLine = _savingLine.contains(line.id);
    final hasAudio = line.audioUrl != null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                line.characterName,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11.5),
                overflow: TextOverflow.ellipsis,
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
                    color: AppColors.primary,
                    onPressed: () => _generateLineAudio(sceneIndex, lineIndex),
                    tooltip: hasAudio ? 'Regenerate audio' : 'Generate audio',
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
