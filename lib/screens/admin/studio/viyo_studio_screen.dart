import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../models/series.dart';
import '../../../models/studio_character.dart';
import '../../../models/studio_location.dart';
import '../../../services/series_service.dart';
import '../../../services/studio_service.dart';
import '../../../services/supabase_service.dart';
import '../../../theme/app_theme.dart';
import 'drama_details_dialog.dart';
import 'viyo_studio_voices_screen.dart';

/// Local-only autosave for an in-progress, not-yet-saved script draft
/// — see _saveDraftLocally. Scoped to the device, not synced anywhere;
/// good enough for a single admin's "don't lose my work if I close
/// the app before hitting Save" safety net.
const _draftPrefsKey = 'viyo_studio_draft_v1';

/// Viyo Studio, Phase 1: paste a script, get back an editable cast of
/// characters (with a generated reference portrait each) and
/// locations (with a generated reference image each), then save that
/// cast onto a series for later episodes to reuse.
///
/// Reached from ViyoStudioHomeScreen, which already asked for the
/// admin key — either fresh ("New Script") or continuing a specific
/// series's already-saved cast ([preselectedSeriesId], which loads
/// that cast in for editing instead of starting blank).
class ViyoStudioScreen extends StatefulWidget {
  final String adminKey;
  final String? preselectedSeriesId;

  const ViyoStudioScreen({super.key, required this.adminKey, this.preselectedSeriesId});

  @override
  State<ViyoStudioScreen> createState() => _ViyoStudioScreenState();
}

class _ViyoStudioScreenState extends State<ViyoStudioScreen> {
  final _scriptController = TextEditingController();

  bool _loadingExisting = false;
  bool _restoredDraft = false;

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
  void initState() {
    super.initState();
    _selectedSeriesId = widget.preselectedSeriesId;
    _loadSpendToday();
    _loadSeries();
    if (widget.preselectedSeriesId != null) {
      _loadExistingCast(widget.preselectedSeriesId!);
    } else {
      _restoreDraftIfAny();
    }
  }

  @override
  void dispose() {
    _scriptController.dispose();
    super.dispose();
  }

  Future<void> _loadSpendToday() async {
    try {
      final spend = await StudioService.spendToday(widget.adminKey);
      if (!mounted) return;
      setState(() => _spendToday = spend);
    } catch (_) {
      // Non-fatal — just leaves the spend bar blank.
    }
  }

  Future<void> _loadSeries() async {
    setState(() => _loadingSeries = true);
    try {
      final series = await SeriesService.getAllSeries(sort: DramaSort.newest, limit: 100);
      if (!mounted) return;
      setState(() {
        _series = series;
        // Only clears an already-set selection that's gone stale (its
        // series got deleted, or this is a restored draft pointing at
        // one that no longer exists) — never picks a series on the
        // admin's behalf when none was ever actually selected. This
        // used to default to series.first (the newest existing
        // series) whenever _selectedSeriesId was null, which meant
        // opening a blank "New Script", pasting an unrelated script,
        // and hitting Save without ever touching the picker silently
        // overwrote whatever drama happened to be most recent —
        // confirmed live: a user's new cast replaced another series'
        // entirely, cast and locations both, with no warning shown
        // anywhere. Leaving it null now means the Series picker shows
        // genuinely empty and "Save Cast to Series" stays disabled
        // (already gated on _selectedSeriesId == null) until the admin
        // either explicitly picks an existing series or taps
        // "+ New Drama".
        if (_selectedSeriesId != null && !series.any((s) => s.id == _selectedSeriesId)) {
          _selectedSeriesId = null;
        }
      });
    } catch (_) {
      // Non-fatal — the admin can still analyze/regenerate without a
      // series picked; they just can't save until this succeeds (the
      // picker shows an empty state and a retry button instead).
    } finally {
      if (mounted) setState(() => _loadingSeries = false);
    }
  }

  /// Creates a brand-new drama right from Studio — previously the
  /// only way to create a series at all was the regular video-upload
  /// flow, so an admin generating a drama end-to-end in Studio had
  /// nowhere to give it a name until an episode was ready to publish.
  Future<void> _createNewDrama() async {
    final userId = SupabaseService.currentUserId;
    if (userId == null) return;
    final details = await showDramaDetailsDialog(context, title: 'New Drama', confirmLabel: 'Create');
    if (details == null) return;
    try {
      final series = await SeriesService.createSeries(
        // Defaults to whoever's running Studio, same as always — the
        // creator picker in the dialog above is how an admin assigns
        // a *different* real account instead.
        userId: details.creatorUserId ?? userId,
        title: details.title,
        description: details.description,
        genre: details.genre,
        contentType: kContentTypeShortDrama,
        orientation: kOrientationVertical,
      );
      if (!mounted) return;
      setState(() {
        _series = [series, ..._series];
        _selectedSeriesId = series.id;
      });
      await _saveDraftLocally();
      _showSnack('Created "${series.title}".');
    } catch (e) {
      if (!mounted) return;
      _showSnack('Could not create drama: ${e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '')}');
    }
  }

  Future<void> _editSelectedDrama() async {
    final seriesId = _selectedSeriesId;
    if (seriesId == null) return;
    final current = _series.firstWhere((s) => s.id == seriesId);
    final details = await showDramaDetailsDialog(
      context,
      initialTitle: current.title,
      initialGenre: current.genre,
      initialDescription: current.description,
      initialCreatorUserId: current.userId,
      initialCreatorLabel: current.authorUsername != null ? '@${current.authorUsername}' : null,
      title: 'Edit Drama',
      confirmLabel: 'Save',
    );
    if (details == null) return;
    try {
      await StudioService.updateDramaDetails(
        widget.adminKey,
        current,
        title: details.title,
        description: details.description,
        genre: details.genre,
        // Only actually changes anything server-side if the admin
        // picked a different account in the dialog — re-sending the
        // same id back is a harmless no-op update.
        creatorUserId: details.creatorUserId,
      );
      if (!mounted) return;
      // Reloaded from scratch rather than patched locally: a changed
      // owner needs this screen's own authorUsername to catch up too
      // (that's a join-time field, never returned by the details
      // endpoint itself), and every episode already published from
      // this series just moved with it server-side.
      await _loadSeries();
      if (!mounted) return;
      _showSnack('Saved "${details.title}".');
    } catch (e) {
      if (!mounted) return;
      _showSnack('Could not save drama: ${e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '')}');
    }
  }

  Future<void> _loadExistingCast(String seriesId) async {
    setState(() => _loadingExisting = true);
    try {
      final cast = await StudioService.getCast(widget.adminKey, seriesId);
      if (!mounted) return;
      setState(() {
        _characters = cast.characters;
        _locations = cast.locations;
      });
    } catch (e) {
      if (!mounted) return;
      _showSnack('Could not load existing cast: ${e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '')}');
    } finally {
      if (mounted) setState(() => _loadingExisting = false);
    }
  }

  Future<void> _restoreDraftIfAny() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_draftPrefsKey);
      if (raw == null) return;
      final draft = jsonDecode(raw) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _scriptController.text = draft['script'] ?? '';
        _characters = ((draft['characters'] as List?) ?? [])
            .map((c) => StudioCharacter.fromJson(c as Map<String, dynamic>))
            .toList();
        _locations = ((draft['locations'] as List?) ?? [])
            .map((l) => StudioLocation.fromJson(l as Map<String, dynamic>))
            .toList();
        _sessionCostCents = (draft['sessionCostCents'] as num?)?.toInt() ?? 0;
        final draftSeriesId = draft['selectedSeriesId'] as String?;
        if (draftSeriesId != null) _selectedSeriesId = draftSeriesId;
        _restoredDraft = _scriptController.text.isNotEmpty || _characters.isNotEmpty || _locations.isNotEmpty;
      });
    } catch (_) {
      // A corrupt/old-shape draft isn't worth failing the screen over
      // — just start blank.
    }
  }

  Future<void> _saveDraftLocally() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hasContent = _scriptController.text.isNotEmpty || _characters.isNotEmpty || _locations.isNotEmpty;
      if (!hasContent) {
        await prefs.remove(_draftPrefsKey);
        return;
      }
      await prefs.setString(
        _draftPrefsKey,
        jsonEncode({
          'script': _scriptController.text,
          'characters': _characters.map((c) => c.toJson()).toList(),
          'locations': _locations.map((l) => l.toJson()).toList(),
          'sessionCostCents': _sessionCostCents,
          'selectedSeriesId': _selectedSeriesId,
        }),
      );
    } catch (_) {
      // Best-effort — losing the autosave write is better handled by
      // just trying again next change than by surfacing an error for
      // a background safety net the admin didn't explicitly ask for.
    }
  }

  Future<void> _clearDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_draftPrefsKey);
    } catch (_) {}
  }

  void _discardDraft() {
    setState(() {
      _scriptController.clear();
      _characters = [];
      _locations = [];
      _sessionCostCents = 0;
      _restoredDraft = false;
    });
    _clearDraft();
  }

  Future<void> _analyzeScript() async {
    final script = _scriptController.text.trim();
    if (script.isEmpty) return;
    setState(() {
      _analyzing = true;
      _analyzeError = null;
    });
    try {
      final result = await StudioService.analyzeScript(widget.adminKey, script);
      if (!mounted) return;
      // Adds to the existing cast rather than replacing it — this is
      // what makes "paste Episode 2's script to add its new
      // characters" actually safe. It used to flatly overwrite
      // _characters/_locations with only whatever this one script
      // mentioned, so analyzing a later episode's script silently
      // dropped every returning character/location not re-mentioned
      // in that episode's text, and hitting Save would then wipe them
      // from the database too. Matched by name (trimmed,
      // case-insensitive) — a name already in the cast is left exactly
      // as-is (keeping its saved portrait, voice, any manual edits);
      // only genuinely new names get appended.
      final existingCharNames = _characters.map((c) => c.name.trim().toLowerCase()).toSet();
      final newCharacters =
          result.characters.where((c) => !existingCharNames.contains(c.name.trim().toLowerCase())).toList();
      final existingLocNames = _locations.map((l) => l.name.trim().toLowerCase()).toSet();
      final newLocations =
          result.locations.where((l) => !existingLocNames.contains(l.name.trim().toLowerCase())).toList();
      setState(() {
        _characters = [..._characters, ...newCharacters];
        _locations = [..._locations, ...newLocations];
        _sessionCostCents += result.costUsdCents;
        _saveMessage = null;
      });
      _showSnack(
        newCharacters.isEmpty && newLocations.isEmpty
            ? 'No new characters or locations found — everyone in this script was already in the cast.'
            : 'Added ${newCharacters.length} new character(s) and ${newLocations.length} new location(s). '
                'Existing cast left untouched.',
      );
      await _loadSpendToday();
      await _saveDraftLocally();
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
      final result = await StudioService.generateCharacterPortrait(widget.adminKey, _characters[index]);
      if (!mounted) return;
      setState(() {
        _characters[index] = _characters[index].copyWith(portraitUrl: result.imageUrl);
        _sessionCostCents += result.costUsdCents;
      });
      await _loadSpendToday();
      await _saveDraftLocally();
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
      final result = await StudioService.generateLocationImage(widget.adminKey, _locations[index]);
      if (!mounted) return;
      setState(() {
        _locations[index] = _locations[index].copyWith(referenceImageUrl: result.imageUrl);
        _sessionCostCents += result.costUsdCents;
      });
      await _loadSpendToday();
      await _saveDraftLocally();
    } catch (e) {
      if (!mounted) return;
      _showSnack(e.toString().replaceFirst(RegExp(r'^Exception:\s*'), ''));
    } finally {
      if (mounted) setState(() => _generatingImages.remove(key));
    }
  }

  Future<void> _saveCast() async {
    final seriesId = _selectedSeriesId;
    if (seriesId == null) return;
    setState(() {
      _saving = true;
      _saveMessage = null;
    });
    try {
      final saved = await StudioService.saveCast(
        widget.adminKey,
        seriesId,
        characters: _characters,
        locations: _locations,
      );
      if (!mounted) return;
      setState(() {
        _characters = saved.characters;
        _locations = saved.locations;
        _saveMessage = 'Saved ${saved.characters.length} characters and ${saved.locations.length} locations.';
        _restoredDraft = false;
      });
      await _clearDraft();
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

  void _goToVoices() {
    final seriesId = _selectedSeriesId;
    if (seriesId == null) return;
    final title = _series.firstWhere((s) => s.id == seriesId, orElse: () => _series.first).title;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ViyoStudioVoicesScreen(adminKey: widget.adminKey, seriesId: seriesId, seriesTitle: title),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: AppColors.background, title: const Text('Viyo Studio')),
      body: _loadingExisting ? const Center(child: CircularProgressIndicator()) : _content(),
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
          if (_restoredDraft) ...[
            const SizedBox(height: 10),
            _draftBanner(),
          ],
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

  Widget _draftBanner() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.coin.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.coin.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.history, size: 16, color: AppColors.coin),
          const SizedBox(width: 8),
          const Expanded(
            child: Text('Restored an unsaved draft from earlier.', style: TextStyle(fontSize: 12.5)),
          ),
          TextButton(onPressed: _discardDraft, child: const Text('Discard', style: TextStyle(fontSize: 12))),
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
            onChanged: (_) => _saveDraftLocally(),
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
                Row(
                  children: [
                    Expanded(
                      child: _editField('Name', c.name, (v) => _updateCharacter(index, c.copyWith(name: v))),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.danger),
                      tooltip: 'Remove ${c.name.isEmpty ? 'character' : c.name}',
                      onPressed: () => _confirmRemoveCharacter(index, c),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: _editField('Age', c.age, (v) => _updateCharacter(index, c.copyWith(age: v))),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _editField('Gender', c.gender, (v) => _updateCharacter(index, c.copyWith(gender: v))),
                    ),
                  ],
                ),
                _editField('Appearance', c.appearance, (v) => _updateCharacter(index, c.copyWith(appearance: v)),
                    maxLines: 2),
                _editField('Clothing', c.clothing, (v) => _updateCharacter(index, c.copyWith(clothing: v))),
                _editField(
                  'Costume lock (optional)',
                  c.costumeLock,
                  (v) => _updateCharacter(index, c.copyWith(costumeLock: v)),
                  hint: 'e.g. "black designer suit jacket, white shirt, black tie" — '
                      'reused exactly in every scene so the outfit never changes',
                ),
                _editField(
                    'Personality', c.personality, (v) => _updateCharacter(index, c.copyWith(personality: v))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _updateCharacter(int index, StudioCharacter updated) {
    setState(() => _characters[index] = updated);
    _saveDraftLocally();
  }

  /// Removal only exists in-memory until Save is pressed, same as
  /// every other edit on this screen — but still worth a confirm, since
  /// a wrong tap here (unlike a wrong tap in a text field) can't be
  /// undone by just typing the value back in.
  Future<void> _confirmRemoveCharacter(int index, StudioCharacter c) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Remove character?'),
        content: Text('Removes ${c.name.isEmpty ? 'this character' : c.name} from the cast. Not permanent until you tap Save.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _characters.removeAt(index));
    _saveDraftLocally();
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
                Row(
                  children: [
                    Expanded(
                      child: _editField('Name', l.name, (v) => _updateLocation(index, l.copyWith(name: v))),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.danger),
                      tooltip: 'Remove ${l.name.isEmpty ? 'location' : l.name}',
                      onPressed: () => _confirmRemoveLocation(index, l),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                _editField('Description', l.description, (v) => _updateLocation(index, l.copyWith(description: v)),
                    maxLines: 2),
                Row(
                  children: [
                    Expanded(
                      child: _editField(
                          'Time of day', l.timeOfDay, (v) => _updateLocation(index, l.copyWith(timeOfDay: v))),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _editField('Mood', l.mood, (v) => _updateLocation(index, l.copyWith(mood: v))),
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

  void _updateLocation(int index, StudioLocation updated) {
    setState(() => _locations[index] = updated);
    _saveDraftLocally();
  }

  Future<void> _confirmRemoveLocation(int index, StudioLocation l) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Remove location?'),
        content: Text('Removes ${l.name.isEmpty ? 'this location' : l.name}. Not permanent until you tap Save.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _locations.removeAt(index));
    _saveDraftLocally();
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

  Widget _editField(String label, String value, ValueChanged<String> onChanged,
      {int maxLines = 1, String? hint}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: TextFormField(
        initialValue: value,
        maxLines: maxLines,
        style: const TextStyle(color: Colors.white, fontSize: 13),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontSize: 11),
          hintText: hint,
          hintStyle: const TextStyle(fontSize: 11, color: AppColors.textMuted),
          hintMaxLines: 2,
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
          Row(
            children: [
              const Expanded(child: Text('Save to series', style: TextStyle(fontWeight: FontWeight.w700))),
              TextButton.icon(
                onPressed: _createNewDrama,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('New Drama', style: TextStyle(fontSize: 12.5)),
                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6)),
              ),
            ],
          ),
          const SizedBox(height: 4),
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
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _selectedSeriesId,
                    isExpanded: true,
                    dropdownColor: AppColors.surface,
                    decoration: const InputDecoration(labelText: 'Series'),
                    items: _series
                        .map((s) => DropdownMenuItem(value: s.id, child: Text(s.title, overflow: TextOverflow.ellipsis)))
                        .toList(),
                    onChanged: (v) {
                      setState(() => _selectedSeriesId = v);
                      _saveDraftLocally();
                    },
                  ),
                ),
                if (_selectedSeriesId != null)
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 20),
                    tooltip: 'Edit drama name/genre',
                    onPressed: _editSelectedDrama,
                  ),
              ],
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
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _goToVoices,
                icon: const Icon(Icons.record_voice_over, size: 18),
                label: const Text('Continue to Voices'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
