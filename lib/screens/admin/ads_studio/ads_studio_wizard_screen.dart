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
import 'ads_result_screen.dart';

const _kPromoteTargets = {
  'viyo': 'VIYO',
  'ollie_ai': 'Ollie AI',
  'other_app': 'Another app',
  'website': 'Website',
  'physical_product': 'Physical product',
  'digital_product': 'Digital product',
  'service': 'Service',
  'business': 'Business',
  'personal_brand': 'Personal brand',
  'film': 'Film / show',
  'music': 'Music',
  'event': 'Event',
  'creator_project': 'Creator project',
};
// Same lists as ads_studio.py (PRODUCT_SUBTYPES, AD_STYLES, CHARACTER_MODES).
const _kSubtypes = {
  'physical_product': ['drink', 'food', 'clothing', 'shoes', 'electronics', 'furniture', 'cosmetics', 'accessories'],
  'service': ['restaurant', 'hotel', 'education', 'cleaning', 'transport', 'consulting', 'health', 'beauty salon'],
  'digital_product': ['software', 'online platform', 'online course', 'game'],
  'event': ['concert', 'conference', 'festival', 'workshop'],
  'music': ['single', 'album', 'tour'],
};
const _kStyles = {
  'auto': 'Let AI choose',
  'product_cinematic': 'Product cinematic',
  'character': 'Character-led',
  'lifestyle': 'Lifestyle',
  'demo': 'Demo / explainer',
  'social': 'Social media',
};
const _kCharacterModes = {
  'auto': 'AI decides',
  'custom': 'I describe one',
  'reuse': 'Reuse a saved one',
  'none': 'No character',
};
final _hexColor = RegExp(r'^#?[0-9a-fA-F]{6}$');
const _kDurations = [8, 15, 30, 45, 60];
const _kAspectRatios = ['9:16', '16:9', '1:1'];
const _kResolutions = ['720p', '1080p'];

// Matches ads_studio.py's AD_ASSET_TYPES exactly. This is what lets
// generation tell a real product asset (must render pixel-exact) from
// a creative reference (fair game for AI reinterpretation) — see
// ads_studio.py's EXACT_ASSET_TYPES and _run_ad_generation.
const _kAssetTypes = {
  'screenshot': 'App / website screenshot',
  'product_photo': 'Product photo',
  'logo': 'Logo',
  'other': 'Other / creative reference',
};

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
  final _brandNameController = TextEditingController();
  // Verified facts besides the features above: the only claims the ad is allowed to make.
  final _factControllers = {
    'benefits': TextEditingController(),
    'prices': TextEditingController(),
    'selling_points': TextEditingController(),
    'specs': TextEditingController(),
  };
  final _colorsController = TextEditingController();
  final _socialController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _charNameController = TextEditingController();
  final _charAppearanceController = TextEditingController();
  final _charClothingController = TextEditingController();
  final _charPersonalityController = TextEditingController();
  final _charVoiceController = TextEditingController();
  String _subtype = '';
  String _adStyle = 'auto';
  String _characterMode = 'auto';
  Map<String, dynamic> _character = {};
  List<AdCharacter>? _savedCharacters;

  late String _promoteTarget = AdsStudioService.isCreator(widget.adminKey) ? 'other_app' : 'viyo';

  /// Creators advertise their own things; "Promote VIYO" and the VIYO screenshot library are admin-only.
  Map<String, String> get _targets => AdsStudioService.isCreator(widget.adminKey)
      ? {for (final e in _kPromoteTargets.entries) if (e.key != 'viyo' && e.key != 'ollie_ai') e.key: e.key == 'other_app' ? 'App' : e.value}
      : _kPromoteTargets;
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
    for (final c in [
      _brandNameController, ..._factControllers.values, _colorsController, _socialController, _phoneController,
      _emailController, _charNameController, _charAppearanceController, _charClothingController,
      _charPersonalityController, _charVoiceController,
    ]) {
      c.dispose();
    }
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
    _brandNameController.text = c.brandName;
    _subtype = c.productSubtype;
    for (final e in _factControllers.entries) {
      e.value.text = (c.facts[e.key] ?? const []).join('\n');
    }
    _colorsController.text = c.brandColors.join(', ');
    _socialController.text = c.socialLinks.join('\n');
    _phoneController.text = c.contact['phone'] ?? '';
    _emailController.text = c.contact['email'] ?? '';
    _adStyle = c.adStyle;
    _characterMode = c.characterMode;
    _character = Map<String, dynamic>.from(c.character);
    _charNameController.text = (_character['name'] ?? '').toString();
    _charAppearanceController.text = (_character['appearance'] ?? '').toString();
    _charClothingController.text = (_character['clothing'] ?? '').toString();
    _charPersonalityController.text = (_character['personality'] ?? '').toString();
    _charVoiceController.text = (_character['voice_style'] ?? '').toString();
  }

  static List<String> _lines(TextEditingController c) =>
      c.text.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

  List<String> get _validColors => _colorsController.text
      .split(RegExp(r'[,\s]+'))
      .map((s) => s.trim())
      .where(_hexColor.hasMatch)
      .map((s) => s.startsWith('#') ? s.toUpperCase() : '#${s.toUpperCase()}')
      .take(4)
      .toList();

  Map<String, dynamic> get _profilePatch {
    final custom = {
      'name': _charNameController.text.trim(),
      'appearance': _charAppearanceController.text.trim(),
      'clothing': _charClothingController.text.trim(),
      'personality': _charPersonalityController.text.trim(),
      'voice_style': _charVoiceController.text.trim(),
    }..removeWhere((_, v) => v.isEmpty);
    return {
      'promote_target': _promoteTarget,
      'brand_name': _brandNameController.text.trim(),
      'product_subtype': (_kSubtypes[_promoteTarget] ?? const []).contains(_subtype) ? _subtype : '',
      'facts': {
        'features': _featureList,
        for (final e in _factControllers.entries) e.key: _lines(e.value),
      },
      'brand_colors': _validColors,
      'social_links': _lines(_socialController).take(5).toList(),
      'contact': {
        if (_phoneController.text.trim().isNotEmpty) 'phone': _phoneController.text.trim(),
        if (_emailController.text.trim().isNotEmpty) 'email': _emailController.text.trim(),
      },
      'ad_style': _adStyle,
      'character_mode': _characterMode,
      // A reused character is set by its own call (portrait and voice come with it), never overwritten here.
      if (_characterMode == 'custom') 'character': custom,
    };
  }

  Future<void> _pickSavedCharacter() async {
    final campaign = _campaign;
    if (campaign == null) return;
    try {
      _savedCharacters ??= await AdsStudioService.listCharacters();
      if (!mounted) return;
      if (_savedCharacters!.isEmpty) {
        _showSnack('No saved characters yet. A character an ad creates is saved here for next time.');
        return;
      }
      final chosen = await showModalBottomSheet<AdCharacter>(
        context: context,
        backgroundColor: AppColors.surface,
        builder: (ctx) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              for (final ch in _savedCharacters!)
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppColors.background,
                    backgroundImage: ch.portraitUrl != null ? NetworkImage(ch.portraitUrl!) : null,
                    child: ch.portraitUrl == null ? const Icon(Icons.person_outline, size: 18) : null,
                  ),
                  title: Text(ch.name.isEmpty ? 'Unnamed character' : ch.name, style: const TextStyle(fontSize: 14)),
                  subtitle: Text((ch.spec['appearance'] ?? '').toString(),
                      maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5)),
                  onTap: () => Navigator.pop(ctx, ch),
                ),
            ],
          ),
        ),
      );
      if (chosen == null) return;
      final updated = await AdsStudioService.reuseCharacter(campaign.id, chosen.id);
      if (!mounted) return;
      setState(() {
        _campaign = updated;
        _characterMode = 'reuse';
        _character = Map<String, dynamic>.from(updated.character);
      });
    } catch (e) {
      if (!mounted) return;
      _showSnack(e.toString().replaceFirst(RegExp(r'^Exception:\s*'), ''));
    }
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
    // Everything — including the picker call itself — lives inside this
    // one try/catch now. The previous version only wrapped the upload
    // network call; FilePicker.platform.pickFiles() and result.files.single
    // sat OUTSIDE it, so an exception from either (pickFiles() throwing on
    // some mobile-browser/webview combos, or .single throwing a bare
    // StateError whenever the browser hands back zero or more than one
    // file — both confirmed real failure modes for file_picker's web
    // backend) propagated uncaught: no snackbar, no thumbnail, nothing —
    // exactly "totally silent" as reported, and exactly why the earlier,
    // narrower fix (which only handled a picked-but-null-bytes file)
    // didn't change anything.
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
      if (result == null || result.files.isEmpty) return; // picker cancelled — nothing to report
      if (result.files.length > 1) {
        _showSnack('Pick one image at a time.');
        return;
      }
      final picked = result.files.first;
      if (picked.bytes == null) {
        _showSnack('Could not read that image — try picking it again, or a different file.');
        return;
      }
      final assetType = await _askAssetType();
      if (assetType == null) return; // cancelled — nothing uploaded
      setState(() => _uploadingAsset = true);
      final asset = await AdsStudioService.uploadAsset(
        widget.adminKey, campaign.id, picked.bytes as Uint8List, picked.name,
        assetType: assetType,
      );
      if (!mounted) return;
      setState(() => _assets = [..._assets, asset]);
    } catch (e) {
      if (!mounted) return;
      _showSnack(e.toString().replaceFirst(RegExp(r'^Exception:\s*'), ''));
    } finally {
      if (mounted) setState(() => _uploadingAsset = false);
    }
  }

  /// Asked right after picking a file, before it uploads — generation
  /// can only tell a real product asset from a creative reference if
  /// the admin actually says which this is (see _kAssetTypes).
  Future<String?> _askAssetType() {
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('What is this image?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: _kAssetTypes.entries
              .map((e) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(e.value, style: const TextStyle(fontSize: 14)),
                    onTap: () => Navigator.pop(ctx, e.key),
                  ))
              .toList(),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        ],
      ),
    );
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
      await AdsStudioService.deleteAsset(widget.adminKey, asset.id, campaignId: _campaign?.id);
      if (!mounted) return;
      setState(() => _assets = _assets.where((a) => a.id != asset.id).toList());
    } catch (e) {
      if (!mounted) return;
      _showSnack(e.toString().replaceFirst(RegExp(r'^Exception:\s*'), ''));
    }
  }

  List<String> get _featureList =>
      _targetFeaturesController.text.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

  // This campaign already went through the paid pipeline at least once
  // (a hook was picked, a script exists, or a video finished/failed) —
  // so editing it doesn't have to mean regenerating anything. A brand
  // new draft has nothing to "just save"; the only useful action is to
  // move it forward.
  bool get _isEditingGenerated => widget.preselectedCampaignId != null && _campaign != null && _campaign!.status != 'draft';

  Map<String, dynamic> get _fieldPatch => {
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
        ..._profilePatch,
      };

  /// Just persists the text/setting fields and goes back to the result
  /// screen — no hooks, script or video generation involved, so this
  /// never spends anything. The right action for fixing a typo (e.g. a
  /// mangled destination link) on a campaign that already has a video.
  Future<void> _saveChangesOnly() async {
    final campaign = _campaign;
    if (campaign == null) return;
    setState(() => _saving = true);
    try {
      await AdsStudioService.updateCampaign(widget.adminKey, campaign.id, _fieldPatch);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => AdsResultScreen(adminKey: widget.adminKey, campaignId: campaign.id),
      ));
    } catch (e) {
      if (!mounted) return;
      _showSnack(e.toString().replaceFirst(RegExp(r'^Exception:\s*'), ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _continueToHooks() async {
    final campaign = _campaign;
    if (campaign == null) return;
    // Re-entering the pipeline on a campaign that already has a finished
    // (or failed) video means a brand new paid Veo/Gemini run later at
    // the generation screen — make that explicit before any field is
    // even saved, rather than letting someone click through screens that
    // each look individually harmless and land on a real charge.
    if (campaign.status == 'ready' || campaign.status == 'failed') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text('Regenerate this ad?'),
          content: Text(
            campaign.status == 'ready'
                ? 'This campaign already has a finished video. Continuing will walk through hooks and script again and, '
                    'once you reach Generate, create a brand new video — a new Veo/Gemini charge, same as the first time.\n\n'
                    'Just fixing a detail like the destination link? Go back and use "Save changes" instead — that\'s free.'
                : 'This will retry generation, which charges for the scenes/voice/video it produces — same as the first attempt.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Continue')),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    if (_characterMode == 'custom' && _charAppearanceController.text.trim().isEmpty) {
      _showSnack('Describe how your character looks, or pick another character option.');
      return;
    }
    if (_characterMode == 'reuse' && (_character['portrait'] ?? _character['saved_id']) == null) {
      _showSnack('Pick a saved character, or choose another character option.');
      return;
    }
    setState(() => _saving = true);
    try {
      final updated = await AdsStudioService.updateCampaign(widget.adminKey, campaign.id, _fieldPatch);
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
        _sectionLabel('Verified facts'),
        _factsSection(),
        const SizedBox(height: 20),
        _sectionLabel('Brand & contact'),
        _brandSection(),
        const SizedBox(height: 20),
        _sectionLabel('2. Reference images (up to 8)'),
        _assetsSection(),
        const SizedBox(height: 20),
        _sectionLabel('Style'),
        _styleSection(),
        const SizedBox(height: 20),
        _sectionLabel('Character'),
        _characterSection(),
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
        if (_isEditingGenerated) ...[
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving ? null : _saveChangesOnly,
              child: Text(_saving ? 'Saving...' : 'Save changes'),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _saving ? null : _continueToHooks,
              child: const Text('Regenerate from hooks (costs again)'),
            ),
          ),
        ] else
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
            children: _targets.entries
                .map((e) => ChoiceChip(
                      label: Text(e.value),
                      selected: _promoteTarget == e.key,
                      onSelected: (_) => setState(() => _promoteTarget = e.key),
                    ))
                .toList(),
          ),
          if (_kSubtypes[_promoteTarget] != null) ...[
            const SizedBox(height: 12),
            const Text('Kind', style: TextStyle(fontSize: 11, color: AppColors.textMuted, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _kSubtypes[_promoteTarget]!
                  .map((t) => ChoiceChip(
                        label: Text(t, style: const TextStyle(fontSize: 12)),
                        selected: _subtype == t,
                        onSelected: (on) => setState(() => _subtype = on ? t : ''),
                      ))
                  .toList(),
            ),
          ],
          if (_promoteTarget == 'viyo' && !AdsStudioService.isCreator(widget.adminKey)) ...[
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
            controller: _brandNameController,
            decoration: const InputDecoration(labelText: 'Brand name (if different)'),
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
            keyboardType: TextInputType.url,
            textCapitalization: TextCapitalization.none,
            autocorrect: false,
            enableSuggestions: false,
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

  Widget _field(TextEditingController c, String label, {int maxLines = 1, String? hint, TextInputType? keyboard}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: c,
          maxLines: maxLines,
          keyboardType: keyboard,
          decoration: InputDecoration(labelText: label, hintText: hint),
          style: const TextStyle(color: Colors.white, fontSize: 13),
          onChanged: c == _colorsController ? (_) => setState(() {}) : null,
        ),
      );

  Widget _factsSection() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text(
              'The ad only says what you write here and in "Real features". Anything else (prices, ingredients, '
              'health or results claims, guarantees) is removed from the script. One per line.',
              style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
            ),
          ),
          _field(_factControllers['benefits']!, 'Benefits', maxLines: 3),
          _field(_factControllers['prices']!, 'Prices', maxLines: 2, hint: 'e.g. RWF 800 per can'),
          _field(_factControllers['selling_points']!, 'Selling points', maxLines: 3),
          _field(_factControllers['specs']!, 'Specs / ingredients / materials', maxLines: 3),
        ],
      ),
    );
  }

  Widget _brandSection() {
    final colors = _validColors;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _field(_colorsController, 'Brand colours (hex, up to 4)', hint: '#E8452C, #1B1B3A'),
          if (colors.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Wrap(
                spacing: 6,
                children: [
                  for (final c in colors)
                    Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: Color(int.parse('FF${c.substring(1)}', radix: 16)),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.white24),
                      ),
                    ),
                ],
              ),
            ),
          _field(_socialController, 'Social accounts (one per line)', maxLines: 3, hint: 'instagram.com/yourbrand'),
          _field(_phoneController, 'Phone', keyboard: TextInputType.phone),
          _field(_emailController, 'Email', keyboard: TextInputType.emailAddress),
        ],
      ),
    );
  }

  Widget _styleSection() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _kStyles.entries
          .map((e) => ChoiceChip(
                label: Text(e.value),
                selected: _adStyle == e.key,
                onSelected: (_) => setState(() => _adStyle = e.key),
              ))
          .toList(),
    );
  }

  Widget _characterSection() {
    final isCreator = AdsStudioService.isCreator(widget.adminKey);
    final modes = {for (final e in _kCharacterModes.entries) if (e.key != 'reuse' || isCreator) e.key: e.value};
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: modes.entries
                .map((e) => ChoiceChip(
                      label: Text(e.value),
                      selected: _characterMode == e.key,
                      onSelected: (_) {
                        setState(() => _characterMode = e.key);
                        if (e.key == 'reuse' && _character['saved_id'] == null) _pickSavedCharacter();
                      },
                    ))
                .toList(),
          ),
          const SizedBox(height: 10),
          Text(
            switch (_characterMode) {
              'auto' => 'The AI uses a character only if it helps this ad. It keeps the same face, clothes and voice in every scene.',
              'custom' => 'One reference portrait is made from your description, then used for every scene with one voice.',
              'reuse' => 'Same portrait and voice as the ad it came from.',
              _ => 'A product-led ad with no people.',
            },
            style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
          ),
          if (_characterMode == 'custom') ...[
            const SizedBox(height: 12),
            _field(_charNameController, 'Name'),
            _field(_charAppearanceController, 'Appearance (required)', maxLines: 2,
                hint: 'e.g. woman in her 20s, short curly hair, round glasses'),
            _field(_charClothingController, 'Clothing'),
            _field(_charPersonalityController, 'Personality'),
            _field(_charVoiceController, 'Voice style', hint: 'e.g. warm, upbeat'),
          ],
          if (_characterMode == 'reuse') ...[
            const SizedBox(height: 12),
            if (_character['name'] != null || _character['appearance'] != null)
              Text('${_character['name'] ?? 'Character'}: ${_character['appearance'] ?? ''}',
                  style: const TextStyle(fontSize: 12.5)),
            TextButton.icon(
              onPressed: _pickSavedCharacter,
              icon: const Icon(Icons.person_search_outlined, size: 16),
              label: const Text('Choose a saved character'),
            ),
          ],
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
          if (_assets.length < 8 && _promoteTarget == 'viyo' && !AdsStudioService.isCreator(widget.adminKey)) _libraryTile(),
        ],
      ),
    );
  }

  Widget _assetTile(AdAsset a) {
    final typeLabel = _kAssetTypes[a.assetType];
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
        if (typeLabel != null)
          Positioned(
            left: 2,
            bottom: 2,
            right: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)),
              child: Text(
                a.assetType == 'other' ? 'creative' : a.assetType.replaceAll('_', ' '),
                style: const TextStyle(fontSize: 8.5, color: Colors.white, fontWeight: FontWeight.w700),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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
