import 'package:flutter/material.dart';
import '../../../models/series.dart';
import '../../../models/studio_character.dart';
import '../../../models/studio_location.dart';
import '../../../services/series_service.dart';
import '../../../services/studio_service.dart';
import '../../../theme/app_theme.dart';

/// Viyo Studio, Phase 1: paste a script, get back an editable cast of
/// characters (with a generated reference portrait each) and
/// locations (with a generated reference image each), then save that
/// cast onto a series for later episodes to reuse.
///
/// Not linked from the app's normal navigation — reached only via the
/// hidden long-press on the Settings screen title (same spot
/// ModerationReviewScreen uses), which is enough friction that a
/// regular user won't stumble into it; the real protection is the
/// admin key itself, asked for every time rather than persisted to
/// disk. See studio_service.dart / viyo_ai's studio.py for why this is
/// admin-only rather than creator-facing for now.
class ViyoStudioScreen extends StatefulWidget {
  const ViyoStudioScreen({super.key});

  @override
  State<ViyoStudioScreen> createState() => _ViyoStudioScreenState();
}

class _ViyoStudioScreenState extends State<ViyoStudioScreen> {
  final _keyController = TextEditingController();
  final _scriptController = TextEditingController();
  String? _adminKey;
  String? _unlockError;

  bool _analyzing = false;
  String? _analyzeError;
  List<StudioCharacter> _characters = [];
  List<StudioLocation> _locations = [];
  int _sessionCostCents = 0;

  StudioSpendToday? _spendToday;

  List<Series> _series = [];
  bool _loadingSeries = false;
  String? _selectedSeriesId;
  bool _saving = false;
  String? _saveMessage;

  // Busy-tracking keyed by "char_<index>" / "loc_<index>" — a plain
  // Set is enough since only one regenerate can be in flight per card
  // (its own button disables itself) but several cards can regenerate
  // at once.
  final Set<String> _generatingImages = {};

  @override
  void dispose() {
    _keyController.dispose();
    _scriptController.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    final key = _keyController.text.trim();
    if (key.isEmpty) return;
    setState(() {
      _adminKey = key;
      _unlockError = null;
    });
    await _loadSpendToday();
    await _loadSeries();
  }

  Future<void> _loadSpendToday() async {
    if (_adminKey == null) return;
    try {
      final spend = await StudioService.spendToday(_adminKey!);
      if (!mounted) return;
      setState(() => _spendToday = spend);
    } catch (e) {
      if (!mounted) return;
      final message = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
      if (message.contains('Invalid admin key')) {
        setState(() {
          _adminKey = null;
          _unlockError = message;
        });
      }
      // Any other failure (e.g. Studio not configured yet) just leaves
      // the spend bar blank — not worth blocking the whole screen over.
    }
  }

  Future<void> _loadSeries() async {
    setState(() => _loadingSeries = true);
    try {
      final series = await SeriesService.getAllSeries(sort: DramaSort.newest, limit: 100);
      if (!mounted) return;
      setState(() {
        _series = series;
        _selectedSeriesId ??= series.isNotEmpty ? series.first.id : null;
      });
    } catch (_) {
      // Non-fatal — the admin can still analyze/regenerate without a
      // series picked; they just can't save until this succeeds (the
      // picker shows an empty state and a retry button instead).
    } finally {
      if (mounted) setState(() => _loadingSeries = false);
    }
  }

  Future<void> _analyzeScript() async {
    final script = _scriptController.text.trim();
    if (script.isEmpty || _adminKey == null) return;
    setState(() {
      _analyzing = true;
      _analyzeError = null;
    });
    try {
      final result = await StudioService.analyzeScript(_adminKey!, script);
      if (!mounted) return;
      setState(() {
        _characters = result.characters;
        _locations = result.locations;
        _sessionCostCents += result.costUsdCents;
        _saveMessage = null;
      });
      await _loadSpendToday();
    } catch (e) {
      if (!mounted) return;
      setState(() => _analyzeError = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), ''));
    } finally {
      if (mounted) setState(() => _analyzing = false);
    }
  }

  Future<void> _generateCharacterPortrait(int index) async {
    final key = 'char_$index';
    setState(() => _generatingImages.add(key));
    try {
      final result = await StudioService.generateCharacterPortrait(_adminKey!, _characters[index]);
      if (!mounted) return;
      setState(() {
        _characters[index] = _characters[index].copyWith(portraitUrl: result.imageUrl);
        _sessionCostCents += result.costUsdCents;
      });
      await _loadSpendToday();
    } catch (e) {
      if (!mounted) return;
      _showSnack(e.toString().replaceFirst(RegExp(r'^Exception:\s*'), ''));
    } finally {
      if (mounted) setState(() => _generatingImages.remove(key));
    }
  }

  Future<void> _generateLocationImage(int index) async {
    final key = 'loc_$index';
    setState(() => _generatingImages.add(key));
    try {
      final result = await StudioService.generateLocationImage(_adminKey!, _locations[index]);
      if (!mounted) return;
      setState(() {
        _locations[index] = _locations[index].copyWith(referenceImageUrl: result.imageUrl);
        _sessionCostCents += result.costUsdCents;
      });
      await _loadSpendToday();
    } catch (e) {
      if (!mounted) return;
      _showSnack(e.toString().replaceFirst(RegExp(r'^Exception:\s*'), ''));
    } finally {
      if (mounted) setState(() => _generatingImages.remove(key));
    }
  }

  Future<void> _saveCast() async {
    final seriesId = _selectedSeriesId;
    if (seriesId == null || _adminKey == null) return;
    setState(() {
      _saving = true;
      _saveMessage = null;
    });
    try {
      final saved = await StudioService.saveCast(
        _adminKey!,
        seriesId,
        characters: _characters,
        locations: _locations,
      );
      if (!mounted) return;
      setState(() {
        _characters = saved.characters;
        _locations = saved.locations;
        _saveMessage = 'Saved ${saved.characters.length} characters and ${saved.locations.length} locations.';
      });
    } catch (e) {
      if (!mounted) return;
      _showSnack(e.toString().replaceFirst(RegExp(r'^Exception:\s*'), ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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
      onRefresh: _loadSpendToday,
      color: AppColors.primary,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _spendBar(),
          const SizedBox(height: 16),
          _scriptInput(),
          if (_characters.isNotEmpty || _locations.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text('Characters (${_characters.length})',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            const SizedBox(height: 10),
            ..._characters.asMap().entries.map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _characterCard(e.key, e.value),
                )),
            const SizedBox(height: 14),
            Text('Locations (${_locations.length})',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            const SizedBox(height: 10),
            ..._locations.asMap().entries.map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _locationCard(e.key, e.value),
                )),
            const SizedBox(height: 20),
            _saveSection(),
          ],
        ],
      ),
    );
  }

  Widget _spendBar() {
    final spend = _spendToday;
    final sessionCost = (_sessionCostCents / 100).toStringAsFixed(2);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: AppTheme.card(),
      child: Row(
        children: [
          const Icon(Icons.attach_money, size: 18, color: AppColors.coin),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              spend == null
                  ? 'This session: \$$sessionCost'
                  : 'Today: \$${spend.spentUsd.toStringAsFixed(2)} / \$${spend.capUsd.toStringAsFixed(2)}  '
                      '·  This session: \$$sessionCost',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _scriptInput() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Paste a script', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          TextField(
            controller: _scriptController,
            maxLines: 10,
            minLines: 6,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: const InputDecoration(hintText: 'Paste the full episode or series script here...'),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _analyzing ? null : _analyzeScript,
              icon: _analyzing
                  ? const SizedBox(
                      width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.auto_awesome, size: 18),
              label: Text(_analyzing ? 'Analyzing...' : 'Analyze Script'),
            ),
          ),
          if (_analyzeError != null) ...[
            const SizedBox(height: 10),
            Text(_analyzeError!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
          ],
        ],
      ),
    );
  }

  Widget _characterCard(int index, StudioCharacter c) {
    final busy = _generatingImages.contains('char_$index');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.card(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _referenceImage(c.portraitUrl, busy: busy, onGenerate: () => _generateCharacterPortrait(index)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _editField('Name', c.name, (v) => setState(() => _characters[index] = c.copyWith(name: v))),
                Row(
                  children: [
                    Expanded(
                      child: _editField(
                          'Age', c.age, (v) => setState(() => _characters[index] = c.copyWith(age: v))),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _editField('Gender', c.gender,
                          (v) => setState(() => _characters[index] = c.copyWith(gender: v))),
                    ),
                  ],
                ),
                _editField('Appearance', c.appearance,
                    (v) => setState(() => _characters[index] = c.copyWith(appearance: v)),
                    maxLines: 2),
                _editField('Clothing', c.clothing,
                    (v) => setState(() => _characters[index] = c.copyWith(clothing: v))),
                _editField('Personality', c.personality,
                    (v) => setState(() => _characters[index] = c.copyWith(personality: v))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _locationCard(int index, StudioLocation l) {
    final busy = _generatingImages.contains('loc_$index');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.card(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _referenceImage(l.referenceImageUrl, busy: busy, onGenerate: () => _generateLocationImage(index),
              tall: true),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _editField('Name', l.name, (v) => setState(() => _locations[index] = l.copyWith(name: v))),
                _editField('Description', l.description,
                    (v) => setState(() => _locations[index] = l.copyWith(description: v)),
                    maxLines: 2),
                Row(
                  children: [
                    Expanded(
                      child: _editField('Time of day', l.timeOfDay,
                          (v) => setState(() => _locations[index] = l.copyWith(timeOfDay: v))),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _editField(
                          'Mood', l.mood, (v) => setState(() => _locations[index] = l.copyWith(mood: v))),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _referenceImage(String? url, {required bool busy, required VoidCallback onGenerate, bool tall = false}) {
    const width = 84.0;
    final height = tall ? 149.0 : 84.0; // 9:16 preview for locations, square-ish for portraits
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
          child: url == null
              ? const Icon(Icons.image_outlined, color: AppColors.textMuted, size: 22)
              : null,
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
                  child: Text(
                    url == null ? 'Generate' : 'Redo',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _editField(String label, String value, ValueChanged<String> onChanged, {int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: TextFormField(
        initialValue: value,
        maxLines: maxLines,
        style: const TextStyle(color: Colors.white, fontSize: 13),
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

  Widget _saveSection() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Save to series', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          if (_loadingSeries)
            const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator(strokeWidth: 2)))
          else if (_series.isEmpty)
            Row(
              children: [
                const Expanded(
                  child: Text('No series found.', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                ),
                TextButton(onPressed: _loadSeries, child: const Text('Retry')),
              ],
            )
          else
            DropdownButtonFormField<String>(
              value: _selectedSeriesId,
              isExpanded: true,
              dropdownColor: AppColors.surface,
              decoration: const InputDecoration(labelText: 'Series'),
              items: _series
                  .map((s) => DropdownMenuItem(value: s.id, child: Text(s.title, overflow: TextOverflow.ellipsis)))
                  .toList(),
              onChanged: (v) => setState(() => _selectedSeriesId = v),
            ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (_saving || _selectedSeriesId == null) ? null : _saveCast,
              child: Text(_saving ? 'Saving...' : 'Save Cast to Series'),
            ),
          ),
          if (_saveMessage != null) ...[
            const SizedBox(height: 10),
            Text(_saveMessage!, style: const TextStyle(color: AppColors.success, fontSize: 13)),
          ],
        ],
      ),
    );
  }
}
