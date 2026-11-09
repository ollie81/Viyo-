import 'package:flutter/material.dart';

import '../../services/creator_studio_service.dart';
import '../../theme/app_theme.dart';
import 'studio_widgets.dart';

/// Starts a paid job after showing its price (the project screen's runner).
typedef StudioRunner = Future<bool> Function(String kind,
    {List<String> targets, String? warning, Map<String, dynamic> extra, String? title});

const _allViews = ['front_full', 'face_closeup', 'left_profile', 'right_profile', 'back_full', 'expressions', 'wardrobe'];

/// The identity part of a character card: create the reference sheet, review
/// and redo single views, edit the identity details, approve and lock, and
/// manage outfits. The creator never writes an AI prompt.
class CharacterIdentitySection extends StatefulWidget {
  final StudioCharacter c;
  final bool busy;
  final StudioRunner run;
  final Future<void> Function() reload;
  const CharacterIdentitySection({super.key, required this.c, required this.busy, required this.run, required this.reload});

  @override
  State<CharacterIdentitySection> createState() => _CharacterIdentitySectionState();
}

class _CharacterIdentitySectionState extends State<CharacterIdentitySection> {
  bool _working = false;

  StudioCharacter get c => widget.c;

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

  void _makeViews(List<String> views, {String? title}) {
    widget.run('portrait', targets: [c.id], extra: {'views': views}, title: title ?? 'Character sheet for ${c.name}');
  }

  Future<void> _preview(StudioView v) async {
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: StudioColors.panel,
        contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        title: Text('${c.name} · ${v.label}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420, maxHeight: 560),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Flexible(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: v.url == null
                    ? const SizedBox(height: 200, child: Icon(Icons.person_outline, size: 48, color: AppColors.textMuted))
                    : InteractiveViewer(child: Image.network(v.url!, fit: BoxFit.contain)),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              switch (v.status) {
                'approved' => 'Approved. Every scene uses this view.',
                'outdated' => 'Made from an older front view, so it may not match. Redo it to match the new front view.',
                _ => v.view == 'front_full'
                    ? 'The front view defines the character: every other view is made from it.'
                    : 'Check it shows the same person as the front view. Approve it, or redo just this view.',
              },
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5, height: 1.35),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
          if (!c.identityLocked) TextButton(onPressed: () => Navigator.pop(ctx, 'redo'), child: const Text('Redo this view')),
          if (!c.identityLocked && v.status == 'draft')
            FilledButton(onPressed: () => Navigator.pop(ctx, 'approve'), child: const Text('Approve')),
        ],
      ),
    );
    if (action == 'approve') {
      await _act(() => CreatorStudioService.approveView(c.id, v.view));
    } else if (action == 'redo') {
      if (v.view == 'front_full' && c.referenceViews.where((x) => x.exists).length > 1) {
        final yes = await _confirm('Redo the front view?',
            'Your other views stay as they are, but they were made from the current front view and will be marked to redo.');
        if (!yes) return;
      }
      _makeViews([v.view], title: 'Redo ${v.label.toLowerCase()}');
    }
  }

  Future<bool> _confirm(String title, String body) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: StudioColors.panel,
          title: Text(title),
          content: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: Text(body, style: const TextStyle(height: 1.4))),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Continue')),
          ],
        ),
      ) ==
      true;

  Future<void> _lock() async {
    final yes = await _confirm('Approve and lock ${c.name}?',
        'Every finished view is approved and ${c.name} looks exactly like this in every scene. You can unlock later to make changes.');
    if (yes) await _act(() => CreatorStudioService.lockIdentity(c.id), done: '${c.name}\'s identity is locked.');
  }

  Future<void> _editIdentity() async {
    final saved = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: StudioColors.panel,
      builder: (ctx) => _IdentityEditor(c: c),
    );
    if (saved != null) await _act(() => CreatorStudioService.updateIdentity(c.id, saved), done: 'Identity saved.');
  }

  Future<void> _outfitDialog({StudioOutfit? o}) async {
    final name = TextEditingController(text: o?.name ?? ''), desc = TextEditingController(text: o?.description ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: StudioColors.panel,
        title: Text(o == null ? 'New outfit for ${c.name}' : 'Edit outfit'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, maxLength: 60, decoration: studioField('Name', hint: 'e.g. Wedding dress').copyWith(counterText: '')),
            const SizedBox(height: 10),
            TextField(controller: desc, maxLines: 3, maxLength: 800,
                decoration: studioField('What they wear', hint: 'Clothes, colours, shoes, jewellery').copyWith(counterText: '')),
            const SizedBox(height: 6),
            const Text('Only the clothes change. Face, hair and body stay exactly the same.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(o == null ? 'Add' : 'Save')),
        ],
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    await _act(() => o == null
        ? CreatorStudioService.addOutfit(c.id, name.text.trim(), desc.text.trim())
        : CreatorStudioService.updateOutfit(o.id, {'name': name.text.trim(), 'description': desc.text.trim()}));
  }

  Widget _statusChip(String status) {
    final (label, color) = switch (status) {
      'approved' => ('Approved', AppColors.success),
      'draft' => ('Review', AppColors.coin),
      'outdated' => ('Redo', AppColors.danger),
      _ => ('Not made', AppColors.textMuted),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
      child: Text(label, style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.w700)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final busy = widget.busy || _working;
    final views = c.referenceViews;
    final locked = c.identityLocked;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 12),
      Row(children: [
        const Icon(Icons.fingerprint, size: 18, color: AppColors.primary),
        const SizedBox(width: 6),
        const Expanded(child: Text('Identity', style: TextStyle(fontWeight: FontWeight.w700))),
        if (locked)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12)),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.lock, size: 13, color: AppColors.success),
              SizedBox(width: 4),
              Text('Locked', style: TextStyle(color: AppColors.success, fontSize: 11.5, fontWeight: FontWeight.w700)),
            ]),
          ),
      ]),
      const SizedBox(height: 4),
      Text(
        !c.hasSheet
            ? 'Create ${c.name}\'s reference sheet once: front, sides, back, face, expressions and clothes, all of the same person. '
                'Every scene then keeps them looking the same.'
            : locked
                ? 'Approved. Every picture and video uses exactly this person.'
                : 'Tap a view to check it, approve it or redo just that one. Then approve and lock.',
        style: const TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.35),
      ),
      const SizedBox(height: 8),
      if (!c.hasSheet)
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.black),
            onPressed: busy ? null : () => _makeViews(_allViews),
            icon: const Icon(Icons.auto_awesome, size: 18),
            label: Text(busy ? 'Working…' : 'Create identity & sheet'),
          ),
        )
      else ...[
        SizedBox(
          height: 150,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: views.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final v = views[i];
              return InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: v.exists ? () => _preview(v) : null,
                child: SizedBox(
                  width: 70,
                  child: Column(children: [
                    AspectFrame(
                      vertical: true,
                      width: 62,
                      imageUrl: v.url,
                      placeholder: Icons.person_outline,
                      overlay: busy && !v.exists
                          ? Container(color: Colors.black45, child: const Center(child: CircularProgressIndicator(strokeWidth: 2)))
                          : null,
                    ),
                    const SizedBox(height: 3),
                    Text(v.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10.5)),
                    const SizedBox(height: 2),
                    _statusChip(v.status),
                  ]),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          if (!locked && c.missingViews.isNotEmpty)
            OutlinedButton.icon(
              onPressed: busy ? null : () => _makeViews(c.missingViews, title: 'Make ${c.missingViews.length} missing views'),
              icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
              label: Text('Make ${c.missingViews.length} missing'),
            ),
          if (!locked)
            FilledButton.icon(
              onPressed: busy || c.lockProblem != null ? null : _lock,
              icon: const Icon(Icons.verified_outlined, size: 18),
              label: const Text('Approve & lock'),
            )
          else
            OutlinedButton.icon(
              onPressed: busy ? null : () => _act(() => CreatorStudioService.unlockIdentity(c.id)),
              icon: const Icon(Icons.lock_open, size: 18),
              label: const Text('Unlock'),
            ),
          TextButton.icon(
            onPressed: busy ? null : _editIdentity,
            icon: Icon(locked ? Icons.visibility_outlined : Icons.tune, size: 18),
            label: Text(locked ? 'Identity details' : 'Edit identity'),
          ),
        ]),
        if (!locked && c.lockProblem != null) ...[
          const SizedBox(height: 4),
          Text(c.lockProblem!, style: const TextStyle(color: AppColors.coin, fontSize: 12)),
        ],
        const SizedBox(height: 12),
        Row(children: [
          const Expanded(child: Text('Outfits', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
          TextButton.icon(
            onPressed: busy ? null : () => _outfitDialog(),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Add outfit'),
          ),
        ]),
        for (final o in c.outfits)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              AspectFrame(vertical: true, width: 34, imageUrl: o.imageUrl, placeholder: Icons.checkroom_outlined),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(o.isDefault ? '${o.name} (main)' : o.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  if (o.description.isNotEmpty)
                    Text(o.description, maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
                ]),
              ),
              if (!o.hasImage)
                TextButton(
                  onPressed: busy
                      ? null
                      : () => widget.run('portrait', targets: [c.id], extra: {'outfit_id': o.id}, title: 'Outfit picture: ${o.name}'),
                  child: const Text('Make picture'),
                ),
              PopupMenuButton<String>(
                color: StudioColors.panel,
                onSelected: (v) async {
                  if (v == 'edit') {
                    await _outfitDialog(o: o);
                  } else if (v == 'redo') {
                    widget.run('portrait', targets: [c.id], extra: {'outfit_id': o.id}, title: 'Redo outfit picture: ${o.name}');
                  } else if (v == 'delete') {
                    if (await _confirm('Remove ${o.name}?', 'Scenes that used it keep the outfit from the scene before.')) {
                      await _act(() => CreatorStudioService.deleteOutfit(o.id));
                    }
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'edit', child: Text('Edit')),
                  if (o.hasImage) const PopupMenuItem(value: 'redo', child: Text('Redo picture')),
                  if (!o.isDefault) const PopupMenuItem(value: 'delete', child: Text('Remove')),
                ],
              ),
            ]),
          ),
      ],
    ]);
  }
}

/// All identity fields, grouped. Read-only while the identity is locked.
class _IdentityEditor extends StatefulWidget {
  final StudioCharacter c;
  const _IdentityEditor({required this.c});
  @override
  State<_IdentityEditor> createState() => _IdentityEditorState();
}

const _fields = <(String, List<(String, String)>)>[
  ('basic', [
    ('age', 'Age or age range'), ('height_cm', 'Height (cm)'), ('build', 'Body build and proportions'),
    ('skin_tone', 'Skin tone'), ('posture', 'Posture'), ('distinguishing', 'Distinguishing features'),
  ]),
  ('face', [
    ('face_shape', 'Face shape'), ('eyes', 'Eyes: shape, colour, spacing'), ('eyebrows', 'Eyebrows'), ('nose', 'Nose'),
    ('lips', 'Lips'), ('jaw_chin', 'Jawline and chin'), ('cheekbones', 'Cheekbones'), ('ears', 'Ears'),
    ('hairline', 'Hairline'), ('hair', 'Hair: colour, texture, style'), ('facial_hair', 'Facial hair'),
    ('marks', 'Freckles, scars, moles, other marks'),
  ]),
  ('body', [
    ('proportions', 'Body proportions'), ('shoulders', 'Shoulders'), ('physique', 'General physique'),
    ('neck_limbs', 'Neck and limb proportions'), ('hands', 'Hands'), ('other', 'Other distinguishing features'),
  ]),
];
const _sectionTitle = {'basic': 'Basic identity', 'face': 'Face', 'body': 'Body'};

class _IdentityEditorState extends State<_IdentityEditor> {
  late final Map<String, TextEditingController> _ctl = {
    for (final (sec, fields) in _fields)
      for (final (k, _) in fields)
        '$sec.$k': TextEditingController(text: '${(widget.c.identity[sec] as Map?)?[k] ?? ''}'),
    'default_outfit': TextEditingController(text: '${widget.c.identity['default_outfit'] ?? ''}'),
  };

  @override
  void dispose() {
    for (final c in _ctl.values) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, dynamic> _result() {
    final out = <String, dynamic>{};
    for (final (sec, fields) in _fields) {
      out[sec] = {
        for (final (k, _) in fields)
          k: k == 'height_cm' ? int.tryParse(_ctl['$sec.$k']!.text.trim()) ?? '' : _ctl['$sec.$k']!.text.trim(),
      };
    }
    out['default_outfit'] = _ctl['default_outfit']!.text.trim();
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final locked = widget.c.identityLocked;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 4),
              child: Row(children: [
                Expanded(
                  child: Text('${widget.c.name}\'s identity',
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                ),
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                locked
                    ? 'Locked. Unlock the character to change these details.'
                    : 'These details never change between scenes. New views use them; views you already have stay as they are.',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.35),
              ),
            ),
            Flexible(
              child: ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 12), shrinkWrap: true, children: [
                for (final (sec, fields) in _fields) ...[
                  Text(_sectionTitle[sec]!, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary)),
                  const SizedBox(height: 8),
                  for (final (k, label) in fields) ...[
                    TextField(
                      controller: _ctl['$sec.$k'],
                      readOnly: locked,
                      keyboardType: k == 'height_cm' ? TextInputType.number : TextInputType.text,
                      maxLength: 200,
                      decoration: studioField(label).copyWith(counterText: ''),
                    ),
                    const SizedBox(height: 8),
                  ],
                  const SizedBox(height: 6),
                ],
                const Text('Main outfit', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary)),
                const SizedBox(height: 8),
                TextField(
                  controller: _ctl['default_outfit'],
                  readOnly: locked,
                  maxLines: 2,
                  maxLength: 800,
                  decoration: studioField('Usual clothes and accessories').copyWith(counterText: ''),
                ),
              ]),
            ),
            if (!locked)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: FilledButton(onPressed: () => Navigator.pop(context, _result()), child: const Text('Save identity')),
              ),
          ]),
        ),
      ),
    );
  }
}
