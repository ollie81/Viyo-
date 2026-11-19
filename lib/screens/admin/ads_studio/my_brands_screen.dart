import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../../services/ad_brands_service.dart';
import '../../../services/ads_studio_service.dart';
import '../../../theme/app_theme.dart';
import 'ads_result_screen.dart';
import 'ads_studio_wizard_screen.dart';

const _kBrandKinds = {
  'physical_product': 'Physical product',
  'digital_product': 'Digital product',
  'other_app': 'App',
  'website': 'Website',
  'service': 'Service',
  'business': 'Business',
  'personal_brand': 'Personal brand',
  'film': 'Film / show',
  'music': 'Music',
  'event': 'Event',
  'creator_project': 'Creator project',
};
const _kBrandFacts = {
  'features': 'Real features',
  'benefits': 'Benefits',
  'prices': 'Prices',
  'selling_points': 'Selling points',
  'specs': 'Specs / ingredients / materials',
};
const _kNewAdStyles = {
  'auto': 'Let AI choose',
  'product_cinematic': 'Product cinematic',
  'character': 'Character-led',
  'lifestyle': 'Lifestyle',
  'demo': 'Demo / explainer',
  'social': 'Social media',
};
// Campaign Universe tracks (same keys as viyo_ai's ads_ideas.TRACKS) and the style each one suggests.
const _kTracks = {
  'product_intro': 'Product introduction',
  'lifestyle': 'Lifestyle',
  'character_story': 'Character story',
  'demo': 'Demonstration',
  'seasonal': 'Seasonal',
  'new_concept': 'New concept',
};
const _kTrackStyle = {
  'product_intro': 'product_cinematic',
  'lifestyle': 'lifestyle',
  'character_story': 'character',
  'demo': 'demo',
  'seasonal': 'social',
  'new_concept': 'auto',
};
final _hex = RegExp(r'^#?[0-9a-fA-F]{6}$');

String _msg(Object e) => e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');

/// My Brands: every brand the creator saved. Each one keeps its details, pictures, verified facts, links,
/// advertising character and the ads made from it, so a new ad starts already filled in.
class MyBrandsScreen extends StatefulWidget {
  const MyBrandsScreen({super.key});

  @override
  State<MyBrandsScreen> createState() => _MyBrandsScreenState();
}

class _MyBrandsScreenState extends State<MyBrandsScreen> {
  bool _loading = true;
  String? _error;
  bool _showArchived = false;
  List<AdBrand> _brands = [];

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
      _brands = await AdBrandsService.list(includeArchived: _showArchived);
    } catch (e) {
      _error = _msg(e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(String? id) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => BrandEditScreen(brandId: id)));
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: const Text('My Brands'),
        actions: [
          TextButton(
            onPressed: () {
              setState(() => _showArchived = !_showArchived);
              _load();
            },
            child: Text(_showArchived ? 'Hide archived' : 'Show archived', style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(null),
        icon: const Icon(Icons.add),
        label: const Text('New brand'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(_error!, style: const TextStyle(color: AppColors.danger)),
                    const SizedBox(height: 10),
                    OutlinedButton(onPressed: _load, child: const Text('Try again')),
                  ]),
                )
              : _brands.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Text(
                          'Save your brand once (logo, product photos, real facts, links and its character) '
                          'and every new ad starts already filled in.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.textSecondary, height: 1.4),
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                        itemCount: _brands.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) => _BrandRow(brand: _brands[i], onTap: () => _open(_brands[i].id)),
                      ),
                    ),
    );
  }
}

class _BrandRow extends StatelessWidget {
  final AdBrand brand;
  final VoidCallback onTap;
  const _BrandRow({required this.brand, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = brand.brandColors.map((c) => Color(int.parse('FF${c.substring(1)}', radix: 16))).toList();
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: 52,
                height: 52,
                color: colors.isNotEmpty ? colors.first : AppColors.surfaceBorder,
                child: brand.logoUrl != null
                    ? Image.network(brand.logoUrl!, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(Icons.storefront_outlined))
                    : Center(
                        child: Text(brand.name.isEmpty ? '?' : brand.name[0].toUpperCase(),
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(brand.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                const SizedBox(height: 3),
                Text(
                  [
                    _kBrandKinds[brand.promoteTarget] ?? brand.promoteTarget,
                    if (brand.productSubtype.isNotEmpty) brand.productSubtype,
                    if (brand.archived) 'archived',
                  ].join(' · '),
                  style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
              ]),
            ),
            for (final c in colors.take(3))
              Container(
                width: 14,
                height: 14,
                margin: const EdgeInsets.only(left: 4),
                decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: Colors.white24)),
              ),
            const Icon(Icons.chevron_right, color: AppColors.textMuted),
          ]),
        ),
      ),
    );
  }
}

/// Create or edit one brand. Once saved, it also shows its pictures, its character, the ads made from it, and
/// "Make a new ad".
class BrandEditScreen extends StatefulWidget {
  final String? brandId;
  const BrandEditScreen({super.key, this.brandId});

  @override
  State<BrandEditScreen> createState() => _BrandEditScreenState();
}

class _BrandEditScreenState extends State<BrandEditScreen> {
  AdBrand? _brand;
  bool _loading = true;
  bool _saving = false;
  bool _uploading = false;
  String? _error;
  AdIdeasPage? _ideas;
  bool _gettingIdeas = false;

  final _name = TextEditingController();
  final _description = TextEditingController();
  final _website = TextEditingController();
  final _cta = TextEditingController();
  final _audience = TextEditingController();
  final _colors = TextEditingController();
  final _socials = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _facts = {for (final k in _kBrandFacts.keys) k: TextEditingController()};
  String _kind = 'physical_product';

  @override
  void initState() {
    super.initState();
    if (widget.brandId == null) {
      _loading = false;
    } else {
      _load(widget.brandId!);
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _description, _website, _cta, _audience, _colors, _socials, _phone, _email, ..._facts.values]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load(String id) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _fill(await AdBrandsService.get(id));
      try {
        _ideas = await AdBrandsService.ideas(id); // reads saved/today's ideas; generates nothing
      } catch (_) {}
    } catch (e) {
      _error = _msg(e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _fill(AdBrand b) {
    _brand = b;
    _name.text = b.name;
    _description.text = b.description;
    _website.text = b.website;
    _cta.text = b.ctaText;
    _audience.text = b.targetAudience;
    _colors.text = b.brandColors.join(', ');
    _socials.text = b.socialLinks.join('\n');
    _phone.text = b.contact['phone'] ?? '';
    _email.text = b.contact['email'] ?? '';
    _kind = _kBrandKinds.containsKey(b.promoteTarget) ? b.promoteTarget : 'physical_product';
    for (final e in _facts.entries) {
      e.value.text = (b.facts[e.key] ?? const []).join('\n');
    }
  }

  static List<String> _lines(TextEditingController c) =>
      c.text.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

  Map<String, dynamic> get _fields => {
        'name': _name.text.trim(),
        'description': _description.text.trim(),
        'promote_target': _kind,
        'website': _website.text.trim(),
        'cta_text': _cta.text.trim(),
        'target_audience': _audience.text.trim(),
        'facts': {for (final e in _facts.entries) e.key: _lines(e.value)},
        'brand_colors': _colors.text
            .split(RegExp(r'[,\s]+'))
            .where(_hex.hasMatch)
            .map((c) => c.startsWith('#') ? c.toUpperCase() : '#${c.toUpperCase()}')
            .take(4)
            .toList(),
        'social_links': _lines(_socials).take(5).toList(),
        'contact': {
          if (_phone.text.trim().isNotEmpty) 'phone': _phone.text.trim(),
          if (_email.text.trim().isNotEmpty) 'email': _email.text.trim(),
        },
      };

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      _snack('Give the brand a name.');
      return;
    }
    setState(() => _saving = true);
    try {
      final b = _brand == null ? await AdBrandsService.create(_fields) : await AdBrandsService.update(_brand!.id, _fields);
      if (!mounted) return;
      setState(() => _fill(b));
      _snack('Brand saved.');
    } catch (e) {
      if (mounted) _snack(_msg(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _setArchived(bool archived) async {
    final b = _brand;
    if (b == null) return;
    try {
      final updated = await AdBrandsService.update(b.id, {'archived': archived});
      if (!mounted) return;
      setState(() => _fill(updated));
      _snack(archived ? 'Archived. Its ads and character are kept.' : 'Restored.');
    } catch (e) {
      if (mounted) _snack(_msg(e));
    }
  }

  Future<void> _addPicture() async {
    final b = _brand;
    if (b == null) return;
    try {
      final picked = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
      if (picked == null || picked.files.isEmpty || picked.files.first.bytes == null) return;
      if (!mounted) return;
      final type = await showModalBottomSheet<String>(
        context: context,
        backgroundColor: AppColors.surface,
        builder: (ctx) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final e in const {'logo': 'Logo', 'product_photo': 'Product photo', 'screenshot': 'Screenshot', 'other': 'Other picture'}.entries)
              ListTile(title: Text(e.value), onTap: () => Navigator.pop(ctx, e.key)),
          ]),
        ),
      );
      if (type == null) return;
      setState(() => _uploading = true);
      final f = picked.files.first;
      await AdBrandsService.uploadAsset(b.id, f.bytes as Uint8List, f.name, type);
      await _load(b.id);
    } catch (e) {
      if (mounted) _snack(_msg(e));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _removePicture(AdBrandAsset a) async {
    final b = _brand;
    if (b == null) return;
    try {
      await AdBrandsService.deleteAsset(b.id, a.id);
      await _load(b.id);
    } catch (e) {
      if (mounted) _snack(_msg(e));
    }
  }

  Future<void> _chooseCharacter() async {
    final b = _brand;
    if (b == null) return;
    try {
      final saved = await AdsStudioService.listCharacters();
      if (!mounted) return;
      if (saved.isEmpty) {
        _snack('No saved characters yet. The character an ad creates is saved for you automatically.');
        return;
      }
      final chosen = await showModalBottomSheet<AdCharacter>(
        context: context,
        backgroundColor: AppColors.surface,
        builder: (ctx) => SafeArea(
          child: ListView(shrinkWrap: true, children: [
            for (final c in saved)
              ListTile(
                leading: CircleAvatar(
                  backgroundImage: c.portraitUrl != null ? NetworkImage(c.portraitUrl!) : null,
                  child: c.portraitUrl == null ? const Icon(Icons.person_outline) : null,
                ),
                title: Text(c.name.isEmpty ? 'Unnamed character' : c.name),
                subtitle: Text((c.spec['appearance'] ?? '').toString(), maxLines: 2, overflow: TextOverflow.ellipsis),
                onTap: () => Navigator.pop(ctx, c),
              ),
          ]),
        ),
      );
      if (chosen == null) return;
      final updated = await AdBrandsService.setCharacter(b.id, chosen.id);
      if (mounted) setState(() => _fill(updated));
    } catch (e) {
      if (mounted) _snack(_msg(e));
    }
  }

  Future<void> _clearCharacter() async {
    final b = _brand;
    if (b == null) return;
    try {
      final updated = await AdBrandsService.clearCharacter(b.id);
      if (mounted) setState(() => _fill(updated));
    } catch (e) {
      if (mounted) _snack(_msg(e));
    }
  }

  Future<void> _newAd({String track = ''}) async {
    final b = _brand;
    if (b == null) return;
    String style = _kTrackStyle[track] ?? 'auto', aspect = '9:16';
    bool useCharacter = b.characterId != null;
    final go = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('New ad for ${b.name}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 4),
              const Text('Filled in from the brand. You can change anything before generating, and you see the '
                  'full price before anything is charged.',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
              const SizedBox(height: 14),
              const Text('Campaign', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final e in _kTracks.entries)
                  ChoiceChip(
                    label: Text(e.value),
                    selected: track == e.key,
                    onSelected: (on) => set(() {
                      track = on ? e.key : '';
                      if (on) style = _kTrackStyle[e.key] ?? style;
                    }),
                  ),
              ]),
              const SizedBox(height: 12),
              const Text('Style', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final e in _kNewAdStyles.entries)
                  ChoiceChip(label: Text(e.value), selected: style == e.key, onSelected: (_) => set(() => style = e.key)),
              ]),
              const SizedBox(height: 12),
              const Text('Shape', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Wrap(spacing: 6, children: [
                for (final a in const ['9:16', '16:9', '1:1'])
                  ChoiceChip(label: Text(a), selected: aspect == a, onSelected: (_) => set(() => aspect = a)),
              ]),
              if (b.characterId != null)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: useCharacter,
                  onChanged: (v) => set(() => useCharacter = v),
                  title: Text('Use ${b.character?.name.isNotEmpty == true ? b.character!.name : 'the brand character'}',
                      style: const TextStyle(fontSize: 13.5)),
                  subtitle: const Text('Same face and voice. Off: a product-only ad.', style: TextStyle(fontSize: 11.5)),
                ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Start the ad')),
              ),
            ]),
          ),
        ),
      ),
    );
    if (go != true) return;
    try {
      final c = await AdBrandsService.newAd(b.id,
          adStyle: style, aspectRatio: aspect, useCharacter: useCharacter, track: track);
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => AdsStudioWizardScreen(adminKey: AdsStudioService.creator, preselectedCampaignId: c.id),
      ));
      if (mounted) _load(b.id);
    } catch (e) {
      if (mounted) _snack(_msg(e));
    }
  }

  Future<void> _getIdeas() async {
    final b = _brand;
    if (b == null) return;
    setState(() => _gettingIdeas = true);
    try {
      final page = await AdBrandsService.newIdeas(b.id);
      if (mounted) setState(() => _ideas = page);
    } catch (e) {
      if (mounted) _snack(_msg(e));
    } finally {
      if (mounted) setState(() => _gettingIdeas = false);
    }
  }

  Future<void> _ideaStatus(AdIdea idea, String status) async {
    final b = _brand;
    if (b == null) return;
    try {
      await AdBrandsService.setIdeaStatus(b.id, idea.id, status);
      final page = await AdBrandsService.ideas(b.id);
      if (mounted) setState(() => _ideas = page);
    } catch (e) {
      if (mounted) _snack(_msg(e));
    }
  }

  Future<void> _useIdea(AdIdea idea) async {
    final b = _brand;
    if (b == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Make "${idea.title}"?'),
        content: const Text('This starts an ad from your brand with this idea. Nothing is charged now: you see the '
            'full price before generating.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Start the ad')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final c = await AdBrandsService.useIdea(b.id, idea.id);
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => AdsStudioWizardScreen(adminKey: AdsStudioService.creator, preselectedCampaignId: c.id),
      ));
      if (mounted) _load(b.id);
    } catch (e) {
      if (mounted) _snack(_msg(e));
    }
  }

  Widget _ideaCard(AdIdea i) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: AppTheme.card(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.secondary.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(i.trackLabel.isEmpty ? (_kTracks[i.track] ?? i.track) : i.trackLabel,
                  style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700)),
            ),
            const Spacer(),
            if (i.status == 'saved') const Icon(Icons.bookmark, size: 16, color: AppColors.coin),
          ]),
          const SizedBox(height: 8),
          Text(i.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
          const SizedBox(height: 4),
          Text('“${i.hook}”', style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 13)),
          if (i.concept.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(i.concept, style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.35)),
          ],
          if (i.beats.isNotEmpty) ...[
            const SizedBox(height: 6),
            for (var n = 0; n < i.beats.length; n++)
              Text('${n + 1}. ${i.beats[n]}', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
          ],
          const SizedBox(height: 8),
          Row(children: [
            ElevatedButton(onPressed: () => _useIdea(i), child: const Text('Make this ad')),
            const SizedBox(width: 6),
            if (i.status != 'saved')
              TextButton(onPressed: () => _ideaStatus(i, 'saved'), child: const Text('Save'))
            else
              TextButton(onPressed: () => _ideaStatus(i, 'new'), child: const Text('Unsave')),
            TextButton(onPressed: () => _ideaStatus(i, 'dismissed'), child: const Text('Dismiss')),
          ]),
        ]),
      );

  List<Widget> _ideasSection(AdBrand b) {
    final page = _ideas;
    return [
      _label('Ideas for today'),
      const Padding(
        padding: EdgeInsets.only(bottom: 8),
        child: Text('Free ideas from your brand and its real facts. Making one into an ad shows the price first.',
            style: TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
      ),
      if (page != null) ...page.today.map(_ideaCard),
      if (page == null || page.canGetMore)
        OutlinedButton.icon(
          onPressed: _gettingIdeas || b.archived ? null : _getIdeas,
          icon: _gettingIdeas
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.lightbulb_outline, size: 16),
          label: Text(page != null && page.today.isNotEmpty ? 'More ideas' : "Get today's ideas (free)"),
        )
      else
        const Text('New ideas tomorrow.', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
      if (page != null && page.saved.isNotEmpty) ...[
        _label('Saved ideas'),
        ...page.saved.map(_ideaCard),
      ],
    ];
  }

  void _openAd(AdBrandCampaign c) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => c.status == 'draft'
          ? AdsStudioWizardScreen(adminKey: AdsStudioService.creator, preselectedCampaignId: c.id)
          : AdsResultScreen(adminKey: AdsStudioService.creator, campaignId: c.id),
    ));
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 8),
        child: Text(t, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
      );

  Widget _field(TextEditingController c, String label, {int maxLines = 1, String? hint, TextInputType? keyboard}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: c,
          maxLines: maxLines,
          keyboardType: keyboard,
          decoration: InputDecoration(labelText: label, hintText: hint),
          style: const TextStyle(color: Colors.white, fontSize: 13),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final b = _brand;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: Text(b == null ? 'New brand' : b.name),
        actions: [
          if (b != null)
            PopupMenuButton<String>(
              onSelected: (v) => _setArchived(v == 'archive'),
              itemBuilder: (_) => [
                PopupMenuItem(value: b.archived ? 'restore' : 'archive', child: Text(b.archived ? 'Restore' : 'Archive')),
              ],
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: AppColors.danger)))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 48),
                  children: [
                    if (b != null && !b.archived) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _newAd,
                          icon: const Icon(Icons.movie_creation_outlined, size: 18),
                          label: const Text('Make a new ad'),
                        ),
                      ),
                    ],
                    _label('Brand'),
                    _field(_name, 'Name'),
                    _field(_description, 'Description', maxLines: 3),
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      for (final e in _kBrandKinds.entries)
                        ChoiceChip(
                          label: Text(e.value, style: const TextStyle(fontSize: 12)),
                          selected: _kind == e.key,
                          onSelected: (_) => setState(() => _kind = e.key),
                        ),
                    ]),
                    const SizedBox(height: 12),
                    _field(_website, 'Website', keyboard: TextInputType.url),
                    _field(_cta, 'Call to action', hint: 'e.g. Find it in shops near you'),
                    _field(_audience, 'Who it is for'),
                    _label('Verified facts'),
                    const Padding(
                      padding: EdgeInsets.only(bottom: 10),
                      child: Text('Ads only say what you write here. One per line.',
                          style: TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
                    ),
                    for (final e in _kBrandFacts.entries) _field(_facts[e.key]!, e.value, maxLines: 2),
                    _label('Look & contact'),
                    _field(_colors, 'Brand colours (hex, up to 4)', hint: '#E8452C, #7A1E5B'),
                    _field(_socials, 'Social accounts (one per line)', maxLines: 3),
                    _field(_phone, 'Phone', keyboard: TextInputType.phone),
                    _field(_email, 'Email', keyboard: TextInputType.emailAddress),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: _saving ? null : _save,
                        child: Text(_saving ? 'Saving...' : (b == null ? 'Save brand' : 'Save changes')),
                      ),
                    ),
                    if (b != null) ..._savedSections(b),
                  ],
                ),
    );
  }

  List<Widget> _savedSections(AdBrand b) => [
        _label('Pictures'),
        SizedBox(
          height: 96,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            for (final a in b.assets)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Stack(children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(a.url, width: 80, height: 96, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(width: 80, height: 96, color: AppColors.surface)),
                  ),
                  Positioned(
                    left: 2,
                    bottom: 2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      color: Colors.black54,
                      child: Text(a.assetType.replaceAll('_', ' '), style: const TextStyle(fontSize: 9)),
                    ),
                  ),
                  Positioned(
                    right: 2,
                    top: 2,
                    child: GestureDetector(
                      onTap: () => _removePicture(a),
                      child: const CircleAvatar(radius: 10, backgroundColor: Colors.black54, child: Icon(Icons.close, size: 12)),
                    ),
                  ),
                ]),
              ),
            GestureDetector(
              onTap: _uploading ? null : _addPicture,
              child: Container(
                width: 80,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.surfaceBorder),
                ),
                child: Center(
                  child: _uploading
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Column(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.add_photo_alternate_outlined, color: AppColors.textMuted),
                          SizedBox(height: 4),
                          Text('Add', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                        ]),
                ),
              ),
            ),
          ]),
        ),
        _label('Advertising character'),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: AppTheme.card(),
          child: b.character == null
              ? Row(children: [
                  const Expanded(
                    child: Text('None yet: the AI decides for each ad. Pick a saved character to use the same face '
                        'and voice in every ad.', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  ),
                  TextButton(onPressed: _chooseCharacter, child: const Text('Choose')),
                ])
              : Row(children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundImage: b.character!.portraitUrl != null ? NetworkImage(b.character!.portraitUrl!) : null,
                    child: b.character!.portraitUrl == null ? const Icon(Icons.person_outline) : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(b.character!.name.isEmpty ? 'Character' : b.character!.name,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text(b.character!.appearance, maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
                    ]),
                  ),
                  TextButton(onPressed: _chooseCharacter, child: const Text('Change')),
                  IconButton(onPressed: _clearCharacter, icon: const Icon(Icons.close, size: 18), tooltip: 'Remove'),
                ]),
        ),
        ..._ideasSection(b),
        _label('Campaign universe'),
        if (b.campaigns.isEmpty)
          const Text('No ads yet.', style: TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
        if (!b.archived) ...[
          Builder(builder: (_) {
            final untried = _kTracks.keys.where((t) => !b.campaigns.any((c) => c.track == t)).toList();
            if (untried.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 6),
              child: Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                const Text('Not tried yet:', style: TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
                for (final t in untried)
                  ActionChip(
                    label: Text(_kTracks[t]!, style: const TextStyle(fontSize: 11.5)),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _newAd(track: t),
                  ),
              ]),
            );
          }),
        ],
        for (final group in [..._kTracks.keys, ''])
          if (b.campaigns.any((c) => c.track == group)) ...[
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 2),
              child: Text(
                '${group.isEmpty ? 'Other ads' : _kTracks[group]} · ${b.campaigns.where((c) => c.track == group).length}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
              ),
            ),
            for (final c in b.campaigns.where((c) => c.track == group))
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: c.thumbnailUrl != null
                    ? Image.network(c.thumbnailUrl!, width: 44, height: 44, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(width: 44, height: 44, color: AppColors.surface))
                    : Container(width: 44, height: 44, color: AppColors.surface, child: const Icon(Icons.movie_outlined, size: 18)),
              ),
              title: Text(_kNewAdStyles[c.adStyle] ?? c.adStyle, style: const TextStyle(fontSize: 13.5)),
              subtitle: Text(
                [c.status.replaceAll('_', ' '), if (c.published) 'on VIYO'].join(' · '),
                style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openAd(c),
            ),
          ],
      ];
}
