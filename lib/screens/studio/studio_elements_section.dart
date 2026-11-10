import 'package:flutter/material.dart';

import '../../services/creator_studio_service.dart';
import '../../theme/app_theme.dart';
import 'studio_identity_section.dart' show StudioRunner;
import 'studio_widgets.dart';

/// Places and objects that look the same in every scene: found in the script
/// by the AI (or added by hand), each with one reference picture that every
/// scene using it gets.
class ElementsSection extends StatefulWidget {
  final StudioProjectDetail d;
  final StudioRunner run;
  final bool Function(String kind) busy;
  final Future<void> Function() reload;
  const ElementsSection({super.key, required this.d, required this.run, required this.busy, required this.reload});

  @override
  State<ElementsSection> createState() => _ElementsSectionState();
}

class _ElementsSectionState extends State<ElementsSection> {
  bool _working = false;

  Future<void> _act(Future<void> Function() action, {String? done}) async {
    setState(() => _working = true);
    try {
      await action();
      await widget.reload();
      if (done != null && mounted) showStudioInfo(context, done);
    } on StudioException catch (e) {
      if (mounted) showStudioError(context, e.message);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _edit({StudioElement? e, String kind = 'location'}) async {
    final name = TextEditingController(text: e?.name ?? '');
    final desc = TextEditingController(text: e?.description ?? '');
    final extra = TextEditingController(text: (e?.isPlace ?? kind == 'location') ? (e?.details['time_of_day'] ?? '') : (e?.details['owner'] ?? ''));
    final isPlace = e?.isPlace ?? kind == 'location';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: StudioColors.panel,
        title: Text(e == null ? (isPlace ? 'Add a place' : 'Add an object') : 'Edit ${e.name}'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: name, maxLength: 80,
                  decoration: studioField('Name', hint: isPlace ? 'e.g. Vance mansion, living room' : 'e.g. Maya\'s black bag, car keys')
                      .copyWith(counterText: '')),
              const SizedBox(height: 10),
              TextField(controller: desc, maxLines: 3, maxLength: 800,
                  decoration: studioField('What it looks like',
                          hint: isPlace ? 'Layout, furniture, colours, light' : 'Colour, material, size, details')
                      .copyWith(counterText: '')),
              const SizedBox(height: 10),
              TextField(controller: extra, maxLength: 120,
                  decoration: studioField(isPlace ? 'Time of day (optional)' : 'Belongs to (optional)').copyWith(counterText: '')),
              if (e != null && e.hasImage) ...[
                const SizedBox(height: 6),
                const Text('Changed the look? Redo its picture so the scenes match.',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
              ],
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(e == null ? 'Add' : 'Save')),
        ],
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    final details = {if (extra.text.trim().isNotEmpty) (isPlace ? 'time_of_day' : 'owner'): extra.text.trim()};
    await _act(() => e == null
        ? CreatorStudioService.addElement(widget.d.project.id, kind, name.text.trim(), desc.text.trim(), details: details)
        : CreatorStudioService.updateElement(e.id, {'name': name.text.trim(), 'description': desc.text.trim(), 'details': details}));
  }

  Future<void> _open(StudioElement e) async {
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: StudioColors.panel,
        title: Text(e.name),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420, maxHeight: 520),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (e.imageUrl != null)
              Flexible(child: ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.network(e.imageUrl!, fit: BoxFit.contain))),
            const SizedBox(height: 8),
            Text(e.description, style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5, height: 1.35)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 'delete'), child: const Text('Remove')),
          TextButton(onPressed: () => Navigator.pop(ctx, 'edit'), child: const Text('Edit')),
          TextButton(onPressed: () => Navigator.pop(ctx, 'picture'), child: Text(e.hasImage ? 'Redo picture' : 'Make picture')),
          if (e.hasImage && e.status != 'approved')
            FilledButton(onPressed: () => Navigator.pop(ctx, 'approve'), child: const Text('Approve')),
        ],
      ),
    );
    switch (action) {
      case 'edit':
        await _edit(e: e);
      case 'picture':
        widget.run('element', targets: [e.id], title: '${e.hasImage ? 'Redo' : 'Make'} picture: ${e.name}');
      case 'approve':
        await _act(() => CreatorStudioService.updateElement(e.id, {'status': 'approved'}));
      case 'delete':
        await _act(() => CreatorStudioService.deleteElement(e.id), done: '${e.name} removed. Scenes keep their pictures.');
    }
  }

  Widget _card(StudioElement e, bool busy) => InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _open(e),
        child: SizedBox(
          width: 104,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: 104,
                height: 104,
                color: const Color(0xFF17173A),
                child: Stack(fit: StackFit.expand, children: [
                  if (e.imageUrl != null)
                    Image.network(e.imageUrl!, fit: BoxFit.cover)
                  else
                    Icon(e.isPlace ? Icons.location_city_outlined : Icons.category_outlined, color: AppColors.textMuted),
                  if (e.status == 'approved')
                    const Positioned(right: 4, top: 4, child: Icon(Icons.verified, size: 16, color: AppColors.success)),
                  if (busy && !e.hasImage)
                    Container(color: Colors.black45, child: const Center(child: CircularProgressIndicator(strokeWidth: 2))),
                ]),
              ),
            ),
            const SizedBox(height: 4),
            Text(e.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, height: 1.25)),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final els = widget.d.elements;
    final places = els.where((e) => e.isPlace).toList();
    final objects = els.where((e) => !e.isPlace).toList();
    final missing = els.where((e) => !e.hasImage).map((e) => e.id).toList();
    final busy = _working || widget.busy('elements') || widget.busy('element');
    return Container(
      decoration: studioPanel(),
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Places & objects', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(height: 4),
        const Text('Locations and things like a phone, keys or a bag. Each gets one picture, and every scene that uses it '
            'gets that picture, so they look the same every time.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.35)),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.black),
            onPressed: busy ? null : () => widget.run('elements'),
            icon: const Icon(Icons.auto_awesome, size: 18),
            label: Text(widget.busy('elements') ? 'Reading the script…' : els.isEmpty ? 'Find them in the script' : 'Find more'),
          ),
          if (missing.isNotEmpty)
            OutlinedButton.icon(
              onPressed: busy ? null : () => widget.run('element', targets: missing),
              icon: const Icon(Icons.image_outlined, size: 18),
              label: Text('Make ${missing.length} picture${missing.length == 1 ? '' : 's'}'),
            ),
          TextButton.icon(onPressed: busy ? null : () => _edit(kind: 'location'),
              icon: const Icon(Icons.add_location_alt_outlined, size: 18), label: const Text('Add place')),
          TextButton.icon(onPressed: busy ? null : () => _edit(kind: 'prop'),
              icon: const Icon(Icons.add_box_outlined, size: 18), label: const Text('Add object')),
        ]),
        for (final (title, list) in [('Places', places), ('Objects', objects)])
          if (list.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 6),
            Wrap(spacing: 10, runSpacing: 10, children: [for (final e in list) _card(e, busy)]),
          ],
      ]),
    );
  }
}
