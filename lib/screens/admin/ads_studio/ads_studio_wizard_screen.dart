import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../../models/ad_asset.dart';
import '../../../models/ad_campaign.dart';
import '../../../services/ads_studio_service.dart';
import '../../../services/supabase_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/dotted_border_box.dart';
import 'ads_hook_screen.dart';

const _kPromoteTargets = {
  'viyo': 'VIYO',
  'ollie_ai': 'Ollie AI',
  'other_app': 'Another app',
  'website': 'Website / product',
};
const _kDurations = [8, 15, 30, 45, 60];
const _kAspectRatios = ['9:16', '16:9', '1:1'];
const _kResolutions = ['720p', '1080p'];

/// Steps 1-4 of the Ads Studio workflow — what to promote, up to 8
/// reference assets, format, audience/objective, plus duration/aspect/
/// resolution/Veo settings. A draft campaign is created immediately on
/// open (or loaded, if [preselectedCampaignId] is given) so assets have
/// somewhere to attach from the first upload — "Continue to Hooks"
/// saves every text field in one call and moves on to hook generation.
class AdsStudioWizardScreen extends StatefulWidget {
  final String adminKey;
  final String? preselectedCampaignId;
  const AdsStudioWizardScreen({super.key, required this.adminKey, this.preselectedCampaignId});

  @override
  State<AdsStudioWizardScreen> createState() => _AdsStudioWizardScreenState();
}

class _AdsStudioWizardScreenState extends State<AdsStudioWizardScreen> {
  bool _loading = true;
  String? _error;
  AdCampaign? _campaign;
  List<AdAsset> _assets = [];
  List<AdFormatInfo> _formats = [];
  List<VeoTierInfo> _veoTiers = [];

  final _targetNameController = TextEditingController();
  final _targetDescriptionController = TextEditingController();
  final _targetFeaturesController = TextEditingController();
  final _audienceController = TextEditingController();
  final _objectiveController = TextEditingController();
  final _destinationController = TextEditingController();
  final _ctaController = TextEditingController();

  String _promoteTarget = 'viyo';
  String? _format;
  int _duration = 15;
  String _aspectRatio = '9:16';
  String _resolution = '720p';
  bool _useVeo = false;
  String _veoTier = 'lite';
  bool _uploadingAsset = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _targetNameController.dispose();
    _targetDescriptionController.dispose();
    _targetFeaturesController.dispose();
    _audienceController.dispose();
    _objectiveController.dispose();
    _destinationController.dispose();
    _ctaController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      _formats = await AdsStudioService.listFormats(widget.adminKey);
      _veoTiers = await AdsStudioService.listVeoTiers(widget.adminKey);
      if (widget.preselectedCampaignId != null) {
        _campaign = await AdsStudioService.getCampaign(widget.adminKey, widget.preselectedCampaignId!);
        _assets = await AdsStudioService.listAssets(widget.adminKey, _campaign!.id);
        _applyCampaignToFields(_campaign!);
      } else {
        final userId = SupabaseService.currentUserId;
        if (userId == null) throw Exception('Not signed in.');
        _campaign = await AdsStudioService.createCampaign(widget.adminKey, userId: userId, promoteTarget: _promoteTarget);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applyCampaignToFields(AdCampaign c) {
    _promoteTarget = c.promoteTarget;
    _targetNameController.text = c.targetName;
    _targetDescriptionController.text = c.targetDescription;
    _targetFeaturesController.text = c.targetFeatures.join('\n');
    _audienceController.text = c.targetAudience;
    _objectiveController.text = c.objective;
    _destinationController.text = c.destinationLink;
    _ctaController.text = c.ctaText;
    _format = c.format;
    _duration = c.durationSeconds;
    _aspectRatio = c.aspectRatio;
    _resolution = c.resolution;
    _useVeo = c.useVeo;
    _veoTier = c.veoTier;
  }

  Future<void> _fillPromoteViyoDefaults() async {
    try {
      final defaults = await AdsStudioService.promoteViyoDefaults(widget.adminKey);
      if (!mounted) return;
      setState(() {
        _promoteTarget = 'viyo';
        _targetNameController.text = defaults.targetName;
        _targetDescriptionController.text = defaults.targetDescription;
        _targetFeaturesController.text = defaults.targetFeatures.join('\n');
        _ctaController.text = defaults.ctaText;
      });
    } catch (e) {
      if (!mounted) return;
      _showSnack(e.toString().replaceFirst(RegExp(r'^Exception:\s*'), ''));
    }
  }

  Future<void> _pickAndUploadAsset() async {
    final campaign = _campaign;
    if (campaign == null || _assets.length >= 8) return;
    final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    if (result == null) return; // picker cancelled — nothing to report
    final picked = result.files.single;
    if (picked.bytes == null) {
      // Abnormal — a file was actually picked but the browser/OS gave
      // back no byte data (seen on some mobile browsers). Previously
      // this silently did nothing, which read as "upload did nothing"
      // with zero feedback — now it says so instead of going quiet.
      _showSnack('Could not read that image — try picking it again, or a different file.');
      return;
    }
    setState(() => _uploadingAsset = true);
    try {
      final asset = await AdsStudioService.uploadAsset(widget.adminKey, campaign.id, picked.bytes as Uint8List, picked.name);
      if (!mounted) return;
      setState(() => _assets = [..._assets, asset]);
    } catch (e) {
      if (!mounted) return;
      _showSnack(e.toString().replaceFirst(RegExp(r'^Exception:\s*'), ''));
    } finally {
      if (mounted) setState(() => _uploadingAsset = false);
    }
  }

  Future<void> _pickFromViyoLibrary() async {
    final campaign = _campaign;
    if (campaign == null || _assets.length >= 8) return;
    try {
      final library = await AdsStudioService.listViyoAssetLibrary(widget.adminKey);
      if (!mounted) return;
      if (library.isEmpty) {
        _showSnack('No Viyo screenshots uploaded to the library yet.');
        return;
      }
      final chosen = await showModalBottomSheet<AdAsset>(
        context: context,
        backgroundColor: AppColors.surface,
        builder: (ctx) => SafeArea(
          child: GridView.builder(
            padding: const EdgeInsets.all(12),
            shrinkWrap: true,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8),
            itemCount: library.length,
            itemBuilder: (_, i) => GestureDetector(
              onTap: () => Navigator.pop(ctx, library[i]),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(library[i].url, fit: BoxFit.cover),
              ),
            ),
          ),
        ),
      );
      if (chosen == null) return;
      final attached = await AdsStudioService.attachLibraryAsset(widget.adminKey, campaign.id, chosen.id);
      if (!mounted) return;
      setState(() => _assets = [..._assets, attached]);
    } catch (e) {
      if (!mounted) return;
      _showSnack(e.toString().replaceFirst(RegExp(r'^Exception:\s*'), ''));
    }
  }

  Future<void> _removeAsset(AdAsset asset) async {
    try {
      await AdsStudioService.deleteAsset(widget.adminKey, asset.id);
      if (!mounted) return;
      setState(() => _assets = _assets.where((a) => a.id != asset.id).toList());
    } catch (e) {
      if (!mounted) return;
      _showSnack(e.toString().replaceFirst(RegExp(r'^Exception:\s*'), ''));
    }
  }

  List<String> get _featureList =>
      _targetFeaturesController.text.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

  Future<void> _continueToHooks() async {
    final campaign = _campaign;
    if (campaign == null) return;
    setState(() => _saving = true);
    try {
      final updated = await AdsStudioService.updateCampaign(widget.adminKey, campaign.id, {
        'target_name': _targetNameController.text.trim(),
        'target_description': _targetDescriptionController.text.trim(),
        'target_features': _featureList,
        'target_audience': _audienceController.text.trim(),
        'objective': _objectiveController.text.trim(),
        'destination_link': _destinationController.text.trim(),
        'cta_text': _ctaController.text.trim(),
        if (_format != null) 'format': _format,
        'duration_seconds': _duration,
        'aspect_ratio': _aspectRatio,
        'resolution': _resolution,
        'use_veo': _useVeo,
        'veo_tier': _veoTier,
      });
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => AdsHookScreen(adminKey: widget.adminKey, campaignId: updated.id),
      ));
    } catch (e) {
      if (!mounted) return;
      _showSnack(e.toString().replaceFirst(RegExp(r'^Exception:\s*'), ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showSnack(String message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: AppColors.background, title: const Text('New Campaign')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, style: const TextStyle(color: AppColors.danger))))
              : _content(),
    );
  }

  Widget _content() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      children: [
        _sectionLabel('1. What are you promoting?'),
        _promoteTargetSection(),
        const SizedBox(height: 20),
        _sectionLabel('2. Reference images (up to 8)'),
        _assetsSection(),
        const SizedBox(height: 20),
        _sectionLabel('3. Format'),
        _formatSection(),
        const SizedBox(height: 20),
        _sectionLabel('4. Audience & objective'),
        _audienceSection(),
        const SizedBox(height: 20),
        _sectionLabel('Video settings'),
        _settingsSection(),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _saving ? null : _continueToHooks,
            child: Text(_saving ? 'Saving...' : 'Continue to Hooks'),
          ),
        ),
      ],
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
      );

  Widget _promoteTargetSection() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _kPromoteTargets.entries
                .map((e) => ChoiceChip(
                      label: Text(e.value),
                      selected: _promoteTarget == e.key,
                      onSelected: (_) => setState(() => _promoteTarget = e.key),
                    ))
                .toList(),
          ),
          if (_promoteTarget == 'viyo') ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _fillPromoteViyoDefaults,
              icon: const Icon(Icons.auto_awesome, size: 16),
              label: const Text('Fill in real VIYO features', style: TextStyle(fontSize: 12.5)),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _targetNameController,
            decoration: const InputDecoration(labelText: 'Name'),
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _targetDescriptionController,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Description'),
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _targetFeaturesController,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'Real features (one per line)'),
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _destinationController,
            decoration: const InputDecoration(labelText: 'Destination link'),
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _ctaController,
            decoration: const InputDecoration(labelText: 'Call to action text'),
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _assetsSection() {
    return SizedBox(
      height: 100,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          ..._assets.map((a) => Padding(padding: const EdgeInsets.only(right: 8), child: _assetTile(a))),
          if (_assets.length < 8) _uploadTile(),
          if (_assets.length < 8 && _promoteTarget == 'viyo') _libraryTile(),
        ],
      ),
    );
  }

  Widget _assetTile(AdAsset a) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(a.url, width: 84, height: 100, fit: BoxFit.cover),
        ),
        Positioned(
          right: 2,
          top: 2,
          child: GestureDetector(
            onTap: () => _removeAsset(a),
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
              child: const Icon(Icons.close, size: 14, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  Widget _uploadTile() {
    return GestureDetector(
      onTap: _uploadingAsset ? null : _pickAndUploadAsset,
      child: SizedBox(
        width: 84,
        height: 100,
        child: DottedBorderBox(
          child: _uploadingAsset
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
              : const Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.add_photo_alternate_outlined, color: AppColors.textMuted, size: 20),
                    SizedBox(height: 4),
                    Text('Upload', style: TextStyle(color: AppColors.textMuted, fontSize: 10.5)),
                  ]),
                ),
        ),
      ),
    );
  }

  Widget _libraryTile() {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: GestureDetector(
        onTap: _pickFromViyoLibrary,
        child: SizedBox(
          width: 84,
          height: 100,
          child: DottedBorderBox(
            child: const Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.collections_outlined, color: AppColors.textMuted, size: 20),
                SizedBox(height: 4),
                Text('Viyo library', style: TextStyle(color: AppColors.textMuted, fontSize: 10.5), textAlign: TextAlign.center),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _formatSection() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ChoiceChip(
          label: const Text('Let AI recommend'),
          selected: _format == null,
          onSelected: (_) => setState(() => _format = null),
        ),
        ..._formats.map((f) => ChoiceChip(
              label: Text(f.label),
              selected: _format == f.key,
              onSelected: (_) => setState(() => _format = f.key),
            )),
      ],
    );
  }

  Widget _audienceSection() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.card(),
      child: Column(
        children: [
          TextField(
            controller: _audienceController,
            decoration: const InputDecoration(labelText: 'Target audience'),
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _objectiveController,
            decoration: const InputDecoration(labelText: 'Objective (e.g. installs, awareness)'),
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _settingsSection() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Duration', style: TextStyle(fontSize: 11, color: AppColors.textMuted, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: _kDurations
                .map((d) => ChoiceChip(label: Text('${d}s'), selected: _duration == d, onSelected: (_) => setState(() => _duration = d)))
                .toList(),
          ),
          const SizedBox(height: 14),
          const Text('Aspect ratio', style: TextStyle(fontSize: 11, color: AppColors.textMuted, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: _kAspectRatios
                .map((a) => ChoiceChip(
                      label: Text(a),
                      selected: _aspectRatio == a,
                      onSelected: (_) => setState(() {
                        _aspectRatio = a;
                        if (a == '1:1') _useVeo = false;
                      }),
                    ))
                .toList(),
          ),
          const SizedBox(height: 14),
          const Text('Resolution', style: TextStyle(fontSize: 11, color: AppColors.textMuted, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: _kResolutions
                .map((r) => ChoiceChip(label: Text(r), selected: _resolution == r, onSelected: (_) => setState(() => _resolution = r)))
                .toList(),
          ),
          const SizedBox(height: 14),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Animate scenes with Veo', style: TextStyle(fontSize: 13)),
            subtitle: Text(
              _aspectRatio == '1:1'
                  ? 'Not available for 1:1 — Veo only supports 16:9/9:16.'
                  : 'Costs more per scene. A dialogue scene uses Veo\'s own generated voice (real sync, but no '
                      'exact wording/voice control) instead of a separate narrator track — otherwise scenes use a '
                      'still-image Ken Burns pan/zoom with a picked narrator voice.',
              style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
            value: _useVeo,
            onChanged: _aspectRatio == '1:1' ? null : (v) => setState(() => _useVeo = v),
          ),
          if (_useVeo && _veoTiers.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Text('Veo quality', style: TextStyle(fontSize: 11, color: AppColors.textMuted, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: _veoTiers
                  .map((t) => ChoiceChip(
                        label: Text('${t.label} (${(t.pricePerSecCents / 100).toStringAsFixed(2)}\$/s)'),
                        selected: _veoTier == t.key,
                        onSelected: (_) => _selectVeoTier(t),
                      ))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _selectVeoTier(VeoTierInfo tier) async {
    if (tier.key != 'standard') {
      setState(() => _veoTier = tier.key);
      return;
    }
    final perClipHigh = (tier.pricePerSecCents * 8 / 100).toStringAsFixed(2);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Use Standard quality?'),
        content: Text(
          'Standard costs \$${(tier.pricePerSecCents / 100).toStringAsFixed(2)}/second — up to ~\$$perClipHigh '
          'per 8-second scene, far more than Lite or Fast. Make sure this campaign is worth it before generating.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Use Standard')),
        ],
      ),
    );
    if (confirmed == true) setState(() => _veoTier = tier.key);
  }
}
