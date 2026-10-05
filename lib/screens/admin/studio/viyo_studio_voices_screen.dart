import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import '../../../models/studio_character.dart';
import '../../../models/studio_voice.dart';
import '../../../services/studio_service.dart';
import '../../../theme/app_theme.dart';

/// Viyo Studio, Phase 2: assign each saved character a distinct
/// text-to-speech voice. Operates on an already-saved series' cast
/// (see StudioService.getCast) rather than in-memory draft data —
/// "the same voice in every episode" only means something once a
/// character has the stable id this screen's endpoints key off of.
///
/// Reached from the end of Phase 1's save flow (ViyoStudioScreen),
/// carrying the same in-memory admin key forward rather than asking
/// for it again.
class ViyoStudioVoicesScreen extends StatefulWidget {
  final String adminKey;
  final String seriesId;
  final String seriesTitle;

  const ViyoStudioVoicesScreen({
    super.key,
    required this.adminKey,
    required this.seriesId,
    required this.seriesTitle,
  });

  @override
  State<ViyoStudioVoicesScreen> createState() => _ViyoStudioVoicesScreenState();
}

class _ViyoStudioVoicesScreenState extends State<ViyoStudioVoicesScreen> {
  final _player = AudioPlayer();

  bool _loading = true;
  String? _error;
  List<StudioCharacter> _characters = [];
  List<StudioVoice> _voices = [];
  int _sessionCostCents = 0;

  bool _assigningAll = false;
  // Keyed by character id — a preview and a save can't both be in
  // flight for the same character at once, but different characters
  // can be mid-preview/mid-save simultaneously.
  final Set<String> _previewing = {};
  final Set<String> _savingVoice = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        StudioService.getCast(widget.adminKey, widget.seriesId),
        StudioService.listVoices(widget.adminKey),
      ]);
      if (!mounted) return;
      setState(() {
        _characters = (results[0] as StudioCastResult).characters;
        _voices = results[1] as List<StudioVoice>;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _autoAssignAll() async {
    setState(() => _assigningAll = true);
    try {
      final updated = await StudioService.assignVoices(widget.adminKey, widget.seriesId);
      if (!mounted) return;
      setState(() => _characters = updated);
    } catch (e) {
      if (!mounted) return;
      _showSnack(e.toString().replaceFirst(RegExp(r'^Exception:\s*'), ''));
    } finally {
      if (mounted) setState(() => _assigningAll = false);
    }
  }

  Future<void> _preview(StudioCharacter character, String voiceName) async {
    final id = character.id!;
    setState(() => _previewing.add(id));
    try {
      final result = await StudioService.previewVoice(widget.adminKey, id, voiceName);
      if (!mounted) return;
      setState(() => _sessionCostCents += result.costUsdCents);
      await _player.stop();
      await _player.play(UrlSource(result.audioUrl));
    } catch (e) {
      if (!mounted) return;
      _showSnack(e.toString().replaceFirst(RegExp(r'^Exception:\s*'), ''));
    } finally {
      if (mounted) setState(() => _previewing.remove(id));
    }
  }

  Future<void> _setVoice(int index, String voiceName) async {
    final character = _characters[index];
    final id = character.id!;
    setState(() {
      _characters[index] = character.copyWith(voiceId: voiceName);
      _savingVoice.add(id);
    });
    try {
      await StudioService.setCharacterVoice(widget.adminKey, id, voiceName);
    } catch (e) {
      if (!mounted) return;
      // Roll back the optimistic update so the dropdown doesn't lie
      // about what's actually saved.
      setState(() => _characters[index] = character);
      _showSnack(e.toString().replaceFirst(RegExp(r'^Exception:\s*'), ''));
    } finally {
      if (mounted) setState(() => _savingVoice.remove(id));
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: Text('Voices · ${widget.seriesTitle}', overflow: TextOverflow.ellipsis),
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
            ElevatedButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }

  Widget _content() {
    if (_characters.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: Text(
            'No characters saved yet — go back and save a cast to this series first.',
            style: TextStyle(color: AppColors.textMuted),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.primary,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _header(),
          const SizedBox(height: 16),
          ..._characters.asMap().entries.map(
                (e) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _characterVoiceCard(e.key, e.value),
                ),
              ),
        ],
      ),
    );
  }

  Widget _header() {
    final sessionCost = (_sessionCostCents / 100).toStringAsFixed(2);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.card(),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'This session: \$$sessionCost',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
            ),
          ),
          TextButton.icon(
            onPressed: _assigningAll ? null : _autoAssignAll,
            icon: _assigningAll
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.auto_fix_high, size: 16),
            label: const Text('Auto-assign all'),
          ),
        ],
      ),
    );
  }

  Widget _characterVoiceCard(int index, StudioCharacter c) {
    final previewing = _previewing.contains(c.id);
    final saving = _savingVoice.contains(c.id);
    final hasVoice = c.voiceId != null && c.voiceId!.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.card(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.surfaceBorder),
              image: c.portraitUrl != null
                  ? DecorationImage(image: NetworkImage(c.portraitUrl!), fit: BoxFit.cover)
                  : null,
            ),
            child: c.portraitUrl == null
                ? const Icon(Icons.person_outline, color: AppColors.textMuted, size: 22)
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                    ),
                    if (!hasVoice)
                      const Padding(
                        padding: EdgeInsets.only(left: 6),
                        child: Icon(Icons.warning_amber_rounded, size: 15, color: AppColors.coin),
                      ),
                  ],
                ),
                Text(
                  '${c.gender} · ${c.age}',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: hasVoice ? c.voiceId : null,
                        isExpanded: true,
                        dropdownColor: AppColors.surface,
                        isDense: true,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: const InputDecoration(
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          hintText: 'Choose a voice',
                        ),
                        items: _voices
                            .map((v) => DropdownMenuItem(
                                  value: v.name,
                                  child: Text('${v.name} — ${v.description}', overflow: TextOverflow.ellipsis),
                                ))
                            .toList(),
                        onChanged: saving ? null : (v) => v == null ? null : _setVoice(index, v),
                      ),
                    ),
                    const SizedBox(width: 6),
                    SizedBox(
                      width: 40,
                      height: 40,
                      child: (previewing || saving)
                          ? const Padding(
                              padding: EdgeInsets.all(10),
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : IconButton(
                              icon: const Icon(Icons.play_circle_outline),
                              color: AppColors.primary,
                              onPressed: hasVoice ? () => _preview(c, c.voiceId!) : null,
                              tooltip: 'Preview',
                            ),
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
}
