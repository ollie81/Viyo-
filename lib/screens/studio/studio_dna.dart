import 'package:flutter/material.dart';

import '../../services/creator_studio_service.dart';
import '../../theme/app_theme.dart';
import 'studio_widgets.dart';

/// Look-alike warnings for the cast (advice, never a block).
class CastCheckBanner extends StatefulWidget {
  final String projectId;
  final Future<Map<String, dynamic>> Function(String id)? load;
  const CastCheckBanner({super.key, required this.projectId, this.load});

  @override
  State<CastCheckBanner> createState() => _CastCheckBannerState();
}

class _CastCheckBannerState extends State<CastCheckBanner> {
  List<Map> pairs = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(CastCheckBanner old) {
    super.didUpdateWidget(old);
    if (old.projectId != widget.projectId) _load();          // another production: its own cast
  }

  void _load() {
    final id = widget.projectId;
    (widget.load ?? CreatorStudioService.castCheck)(id).then((v) {
      if (mounted && id == widget.projectId) setState(() => pairs = ((v['pairs'] as List?) ?? const []).cast<Map>());
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    if (pairs.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: studioPanel(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.people_alt_outlined, size: 18, color: AppColors.coin),
          SizedBox(width: 8),
          Expanded(child: Text('Characters who look alike', style: TextStyle(fontWeight: FontWeight.w800))),
        ]),
        const SizedBox(height: 6),
        for (final p in pairs.take(5))
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text('${p['problem']} ${p['fix']}', style: const TextStyle(fontSize: 12.5, height: 1.35)),
          ),
      ]),
    );
  }
}

Future<void> showCharacterDna(BuildContext context, String characterId) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: StudioColors.panel,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        builder: (_, scroll) => FutureBuilder<Map<String, dynamic>>(
          future: CreatorStudioService.characterDna(characterId),
          builder: (_, snap) => snap.hasData
              ? CharacterDnaView(dna: snap.data!, controller: scroll)
              : Center(
                  child: snap.hasError
                      ? Text('Couldn\'t load: ${snap.error}', style: const TextStyle(color: AppColors.danger))
                      : const CircularProgressIndicator()),
        ),
      ),
    );

/// The Character DNA card.
class CharacterDnaView extends StatelessWidget {
  final Map<String, dynamic> dna;
  final ScrollController? controller;
  const CharacterDnaView({super.key, required this.dna, this.controller});

  static const _labels = {
    'role': 'Role', 'history': 'History', 'wants': 'Wants', 'want': 'Wants', 'need': 'Needs', 'fears_losing': 'Fears losing',
    'hides': 'Hides', 'secret': 'Secret', 'strength': 'Strength', 'weakness': 'Weakness', 'flaw': 'Flaw',
    'inner_conflict': 'Inner conflict', 'arc': 'Arc',
  };

  @override
  Widget build(BuildContext context) {
    final look = Map<String, dynamic>.from(dna['look'] as Map? ?? const {});
    final identity = Map<String, dynamic>.from(look['identity'] as Map? ?? const {});
    final views = ((look['reference_views'] as List?) ?? const []).cast<Map>().where((v) => v['url'] != null).toList();
    final voice = Map<String, dynamic>.from(dna['voice'] as Map? ?? const {});
    final person = Map<String, dynamic>.from(dna['person'] as Map? ?? const {});
    final story = Map<String, dynamic>.from(dna['story'] as Map? ?? const {});
    final rels = ((dna['relationships'] as List?) ?? const []).cast<Map>();
    final emo = dna['emotional_state'] as Map?;
    final cons = Map<String, dynamic>.from(dna['consistency'] as Map? ?? const {});
    final alike = ((dna['look_alikes'] as List?) ?? const []).cast<Map>();
    final appears = ((dna['appears_in_scenes'] as List?) ?? const []).join(', ');
    String sect(String k) => ((identity[k] as Map?) ?? const {}).entries.where((e) => '${e.value}'.isNotEmpty)
        .map((e) => '${e.value}').join(' · ');
    return ListView(controller: controller, padding: const EdgeInsets.fromLTRB(18, 14, 18, 28), children: [
      Row(children: [
        Expanded(child: Text('${dna['name']}', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800))),
        if (dna['locked'] == true)
          const Chip(visualDensity: VisualDensity.compact, avatar: Icon(Icons.lock, size: 14), label: Text('Locked')),
      ]),
      const Text('Character DNA', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
      if (views.isNotEmpty) ...[
        const SizedBox(height: 10),
        SizedBox(
          height: 120,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            for (final v in views)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network('${v['url']}', width: 80, height: 120, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox(width: 80)),
                ),
              ),
          ]),
        ),
      ],
      _block('Look', [
        if (sect('basic').isNotEmpty) sect('basic'),
        if (sect('face').isNotEmpty) sect('face'),
        if ('${identity['default_outfit'] ?? ''}'.isNotEmpty) 'Usually wears: ${identity['default_outfit']}',
        for (final o in ((look['outfits'] as List?) ?? const []).cast<Map>()) 'Outfit "${o['name']}": ${o['description']}',
      ]),
      _block('Voice', [
        '${voice['voice'] ?? 'No voice yet'}${voice['locked'] == true ? ' (locked)' : ''}',
        if ('${voice['description'] ?? ''}'.isNotEmpty) '${voice['description']}',
      ]),
      _block('Personality', [
        if ('${person['personality'] ?? ''}'.isNotEmpty) '${person['personality']}',
        if ('${person['description'] ?? ''}'.isNotEmpty) '${person['description']}',
      ]),
      _block('Story', [for (final e in story.entries) '${_labels[e.key] ?? e.key}: ${e.value}']),
      _block('Relationships', [for (final r in rels) '${r['between']}: ${r['kind']}${r['tension'] != null ? ' (${r['tension']})' : ''}']),
      _block('Now', [
        if (emo != null) 'Feeling ${emo['emotion']} (scene ${emo['scene']})',
        if (appears.isNotEmpty) 'In scenes $appears',
        'Pictures checked: ${cons['checked'] ?? 0} of ${cons['shots'] ?? 0} shots'
            '${(cons['flagged'] ?? 0) > 0 ? ' · ${cons['flagged']} drawn differently' : ''}',
      ]),
      if (alike.isNotEmpty) _block('Looks like', [for (final p in alike) '${p['problem']} ${p['fix']}']),
    ]);
  }

  Widget _block(String title, List<String> lines) => lines.isEmpty
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
            const SizedBox(height: 4),
            for (final l in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(l, style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.35)),
              ),
          ]),
        );
}
