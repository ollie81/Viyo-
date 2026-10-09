import 'package:flutter/material.dart';
import '../../../services/ads_studio_service.dart';
import '../../../theme/app_theme.dart';
import 'ads_generation_screen.dart';

/// The editable scene-by-scene plan built around the chosen hook —
/// generated once, then fully editable before anything actually
/// renders, same "draft held until a deliberate save" posture Viyo
/// Studio's own cast-editing screen uses.
class AdsScriptScreen extends StatefulWidget {
  final String adminKey;
  final String campaignId;
  const AdsScriptScreen({super.key, required this.adminKey, required this.campaignId});

  @override
  State<AdsScriptScreen> createState() => _AdsScriptScreenState();
}

class _AdsScriptScreenState extends State<AdsScriptScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _error;
  List<Map<String, dynamic>> _scenes = [];
  // Tracked so "Save and continue" can warn before it leads to a real
  // charge: a campaign that already finished once means this run is a
  // genuine regenerate, not the first (necessary) generation.
  String _campaignStatus = 'draft';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final campaign = await AdsStudioService.getCampaign(widget.adminKey, widget.campaignId);
      _campaignStatus = campaign.status;
      if (campaign.hasScript) {
        setState(() => _scenes = campaign.script!);
      } else {
        await _generate();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _generate() async {
    setState(() => _error = null);
    try {
      final result = await AdsStudioService.generateScript(widget.adminKey, widget.campaignId);
      if (!mounted) return;
      setState(() => _scenes = result.scenes);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), ''));
    }
  }

  void _updateScene(int index, String field, dynamic value) {
    setState(() {
      _scenes[index] = {..._scenes[index], field: value};
    });
  }

  Future<void> _saveAndContinue() async {
    // Last checkpoint before the next screen fires the paid Veo/Gemini
    // job automatically on load — confirm here if a finished video
    // already exists, since that means this run replaces it rather than
    // producing the campaign's first one.
    if (_campaignStatus == 'ready') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text('Generate a new video?'),
          content: const Text(
            'This campaign already has a finished video. Continuing starts a brand new generation — a real Veo/Gemini '
            'charge, same as the first run.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Generate')),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    setState(() => _saving = true);
    try {
      final normalized = _scenes
          .asMap()
          .entries
          .map((e) => {
                'order': e.key + 1,
                'seconds': (e.value['seconds'] as num?)?.toDouble() ?? 3.0,
                'visual_description': e.value['visual_description'] ?? '',
                'camera_shot': e.value['camera_shot'] ?? '',
                'dialogue_or_vo': e.value['dialogue_or_vo'] ?? '',
                'caption_text': e.value['caption_text'] ?? '',
                'is_cta': e.key == _scenes.length - 1,
              })
          .toList();
      await AdsStudioService.saveScript(widget.adminKey, widget.campaignId, normalized);
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => AdsGenerationScreen(adminKey: widget.adminKey, campaignId: widget.campaignId),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst(RegExp(r'^Exception:\s*'), ''))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: const Text('Script'),
        actions: [
          IconButton(tooltip: 'Regenerate script', icon: const Icon(Icons.refresh), onPressed: _loading ? null : _generate),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(_error!, style: const TextStyle(color: AppColors.danger), textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      ElevatedButton(onPressed: _generate, child: const Text('Retry')),
                    ]),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                  children: [
                    ..._scenes.asMap().entries.map((e) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _sceneCard(e.key, e.value),
                        )),
                  ],
                ),
      bottomNavigationBar: _loading || _error != null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _saveAndContinue,
                    child: Text(_saving ? 'Saving...' : 'Save & Continue to Generate'),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _sceneCard(int index, Map<String, dynamic> scene) {
    final isCta = index == _scenes.length - 1;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.card(borderColor: isCta ? AppColors.coin : null),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Scene ${index + 1}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
              if (isCta) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(color: AppColors.coin.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                  child: const Text('CTA', style: TextStyle(fontSize: 10, color: AppColors.coin, fontWeight: FontWeight.w700)),
                ),
              ],
              const Spacer(),
              Text('${(scene['seconds'] as num?)?.toStringAsFixed(1) ?? '3.0'}s', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 8),
          _field('Visual', scene['visual_description']?.toString() ?? '', maxLines: 2, onChanged: (v) => _updateScene(index, 'visual_description', v)),
          _field('Camera shot', scene['camera_shot']?.toString() ?? '', onChanged: (v) => _updateScene(index, 'camera_shot', v)),
          _field('Dialogue / voiceover', scene['dialogue_or_vo']?.toString() ?? '', maxLines: 2, onChanged: (v) => _updateScene(index, 'dialogue_or_vo', v)),
          _field('On-screen caption', scene['caption_text']?.toString() ?? '', maxLines: 2, onChanged: (v) => _updateScene(index, 'caption_text', v)),
        ],
      ),
    );
  }

  Widget _field(String label, String value, {int maxLines = 1, required ValueChanged<String> onChanged}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: TextFormField(
        initialValue: value,
        maxLines: maxLines,
        style: const TextStyle(color: Colors.white, fontSize: 13),
        decoration: InputDecoration(labelText: label, labelStyle: const TextStyle(fontSize: 11), isDense: true),
        onChanged: onChanged,
      ),
    );
  }
}
