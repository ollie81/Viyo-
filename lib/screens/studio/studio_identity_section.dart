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
    final n = c.guessedFields.length;
    final yes = await _confirm('Approve and lock ${c.name}?',
        '${n > 0 ? '$n detail${n == 1 ? ' is' : 's are'} still an AI guess you haven\'t checked. ' : ''}'
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
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _OutfitDialog(characterName: c.name, outfit: o),
    );
    if (result == null) return;
    final parts = Map<String, String>.from(result['parts'] as Map);
    await _act(() => o == null
        ? CreatorStudioService.addOutfit(c.id, result['name'], result['description'],
            parts: parts, temporary: result['is_temporary'] == true)
        : CreatorStudioService.updateOutfit(o.id, {
            'name': result['name'], 'description': result['description'], 'parts': parts,
            'is_temporary': result['is_temporary'] == true,
          }));
  }

  void _outfitPicture(StudioOutfit o, {bool redo = false}) {
    if (!c.hasSheet) {
      showStudioError(context, 'Create ${c.name}\'s reference sheet first: outfit pictures are made from the front view.');
      return;
    }
    widget.run('portrait', targets: [c.id], extra: {'outfit_id': o.id}, title: '${redo ? 'Redo outfit' : 'Outfit'} picture: ${o.name}');
  }

  Widget _tag(String text, Color color) => Container(
        margin: const EdgeInsets.only(left: 6),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(8)),
        child: Text(text, style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.w700)),
      );

  Widget _outfitRow(StudioOutfit o, bool busy) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AspectFrame(vertical: true, width: 34, imageUrl: o.imageUrl, placeholder: Icons.checkroom_outlined),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(o.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                if (o.isDefault) _tag('Main', AppColors.primary),
                if (o.isTemporary) _tag('Temporary', AppColors.coin),
                if (o.imageOutdated) _tag('Picture out of date', AppColors.danger),
              ]),
              if (o.summary.isNotEmpty)
                Text(o.summary, maxLines: 3, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5, height: 1.3)),
            ]),
          ),
          if (!o.hasImage || o.imageOutdated)
            TextButton(
              onPressed: busy ? null : () => _outfitPicture(o, redo: o.hasImage),
              child: Text(o.hasImage ? 'Update picture' : 'Make picture'),
            ),
          PopupMenuButton<String>(
            color: StudioColors.panel,
            onSelected: (v) async {
              if (v == 'edit') {
                await _outfitDialog(o: o);
              } else if (v == 'redo') {
                _outfitPicture(o, redo: true);
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
      );

  /// Saved outfits, AI suggestions waiting for a decision, and outfits from
  /// earlier episodes ready to reuse.
  Widget _outfits(bool busy) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Expanded(child: Text('Outfits', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
          TextButton.icon(
            onPressed: busy ? null : () => _outfitDialog(),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Add outfit'),
          ),
        ]),
        const Text('Clothes can change in any scene. Face, hair and body always stay the same.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
        const SizedBox(height: 8),
        for (final o in c.outfits) _outfitRow(o, busy),
        if (c.outfitSuggestions.isNotEmpty) ...[
          const SizedBox(height: 6),
          const Row(children: [
            Icon(Icons.auto_awesome, size: 15, color: AppColors.coin),
            SizedBox(width: 6),
            Text('Suggested from the screenplay', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5, color: AppColors.coin)),
          ]),
          const SizedBox(height: 6),
          for (final o in c.outfitSuggestions)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.coin.withValues(alpha: 0.35)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(o.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                if (o.reason.isNotEmpty) Text(o.reason, style: const TextStyle(fontSize: 12, height: 1.3)),
                if (o.summary.isNotEmpty)
                  Text(o.summary, style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5, height: 1.3)),
                const SizedBox(height: 6),
                Wrap(spacing: 8, runSpacing: 4, children: [
                  if (o.suggestedScenes.isNotEmpty)
                    FilledButton(
                      onPressed: busy ? null : () => _act(() => CreatorStudioService.acceptOutfit(o.id), done: 'Outfit saved and used.'),
                      child: Text('Use in ${o.suggestedScenes.length} scene${o.suggestedScenes.length == 1 ? '' : 's'}'),
                    ),
                  OutlinedButton(
                    onPressed: busy
                        ? null
                        : () => _act(() => CreatorStudioService.acceptOutfit(o.id, useInSuggestedScenes: false), done: 'Outfit saved.'),
                    child: const Text('Save only'),
                  ),
                  TextButton(
                    onPressed: busy ? null : () => _act(() => CreatorStudioService.deleteOutfit(o.id)),
                    child: const Text('Dismiss'),
                  ),
                ]),
              ]),
            ),
        ],
        if (c.outfitLibrary.isNotEmpty) ...[
          const SizedBox(height: 6),
          const Text('From earlier episodes', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
          const SizedBox(height: 6),
          for (final o in c.outfitLibrary)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(children: [
                AspectFrame(vertical: true, width: 28, imageUrl: o.imageUrl, placeholder: Icons.checkroom_outlined),
                const SizedBox(width: 10),
                Expanded(child: Text(o.name, style: const TextStyle(fontSize: 13))),
                TextButton(
                  onPressed: busy ? null : () => _act(() => CreatorStudioService.importOutfit(c.id, o.id), done: '${o.name} added.'),
                  child: const Text('Use'),
                ),
              ]),
            ),
        ],
      ]);

  String _fieldLabel(String key) {
    for (final (sec, fields) in _fields) {
      for (final (k, label) in fields) {
        if ('$sec.$k' == key) return label.toLowerCase();
      }
    }
    return key == 'default_outfit' ? 'usual clothes' : key;
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
        if (!locked && c.guessedFields.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.fromLTRB(10, 8, 6, 4),
            decoration: BoxDecoration(
              color: AppColors.coin.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.coin.withValues(alpha: 0.3)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                '${c.guessedFields.length} detail${c.guessedFields.length == 1 ? ' was' : 's were'} not in the story, so the AI '
                'guessed ${c.guessedFields.length == 1 ? 'it' : 'them'} (e.g. ${_fieldLabel(c.guessedFields.first)}). Check and correct them.',
                style: const TextStyle(fontSize: 12, height: 1.35),
              ),
              Wrap(spacing: 4, children: [
                TextButton(onPressed: busy ? null : _editIdentity, child: const Text('Check details')),
                TextButton(
                  onPressed: busy
                      ? null
                      : () => _act(() => CreatorStudioService.updateIdentity(c.id, {'_confirm': 'all'}), done: 'Details confirmed.'),
                  child: const Text('They\'re right'),
                ),
              ]),
            ]),
          ),
        ],
      ],
      const SizedBox(height: 12),
      _outfits(busy),
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
  late final Set<String> _guessed = {...widget.c.guessedFields};
  final Set<String> _confirmed = {};
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
    if (_confirmed.isNotEmpty) out['_confirm'] = _confirmed.toList();
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
                      decoration: studioField(label).copyWith(
                        counterText: '',
                        helperText: _guessed.contains('$sec.$k') && !_confirmed.contains('$sec.$k')
                            ? 'AI guess: not in the story. Correct it, or tick it if it\'s right.'
                            : null,
                        helperStyle: const TextStyle(color: AppColors.coin, fontSize: 11),
                        suffixIcon: _guessed.contains('$sec.$k') && !locked
                            ? IconButton(
                                tooltip: 'This is right',
                                icon: Icon(_confirmed.contains('$sec.$k') ? Icons.check_circle : Icons.check_circle_outline,
                                    color: _confirmed.contains('$sec.$k') ? AppColors.success : AppColors.coin, size: 20),
                                onPressed: () => setState(() => _confirmed.contains('$sec.$k')
                                    ? _confirmed.remove('$sec.$k')
                                    : _confirmed.add('$sec.$k')),
                              )
                            : null,
                      ),
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


/// Name, the four outfit parts (each changes on its own), notes, and whether
/// it is a temporary change.
class _OutfitDialog extends StatefulWidget {
  final String characterName;
  final StudioOutfit? outfit;
  const _OutfitDialog({required this.characterName, this.outfit});
  @override
  State<_OutfitDialog> createState() => _OutfitDialogState();
}

class _OutfitDialogState extends State<_OutfitDialog> {
  late final _name = TextEditingController(text: widget.outfit?.name ?? '');
  late final _notes = TextEditingController(text: widget.outfit?.description ?? '');
  late final Map<String, TextEditingController> _parts = {
    for (final k in StudioOutfit.parts) k: TextEditingController(text: widget.outfit?.partValues[k] ?? ''),
  };
  late bool _temporary = widget.outfit?.isTemporary ?? false;

  static const _hints = {
    'clothing': 'e.g. navy hospital scrubs, white coat',
    'shoes': 'e.g. white clogs',
    'accessories': 'e.g. ID badge, silver watch',
    'makeup': 'e.g. none, tired eyes',
  };

  @override
  void dispose() {
    _name.dispose();
    _notes.dispose();
    for (final c in _parts.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: StudioColors.panel,
      title: Text(widget.outfit == null ? 'New outfit for ${widget.characterName}' : 'Edit outfit'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: _name, maxLength: 60,
                decoration: studioField('Name', hint: 'Casual, Work, Wedding, Hospital, Nightwear…').copyWith(counterText: '')),
            const SizedBox(height: 10),
            for (final k in StudioOutfit.parts) ...[
              TextField(controller: _parts[k], maxLength: 300,
                  decoration: studioField(StudioOutfit.partLabels[k]!, hint: _hints[k]).copyWith(counterText: '')),
              const SizedBox(height: 8),
            ],
            TextField(controller: _notes, maxLines: 2, maxLength: 800,
                decoration: studioField('Other notes (optional)', hint: 'Condition, colours, style').copyWith(counterText: '')),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _temporary,
              onChanged: (v) => setState(() => _temporary = v),
              title: const Text('Temporary change', style: TextStyle(fontSize: 13.5)),
              subtitle: const Text('For a short part of the story (e.g. soaked by rain). Not offered in later episodes.',
                  style: TextStyle(fontSize: 11.5)),
            ),
            const Text('Only what they wear changes. Face, hair, body and height stay exactly the same.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            if (_name.text.trim().isEmpty) return;
            Navigator.pop(context, {
              'name': _name.text.trim(),
              'description': _notes.text.trim(),
              'parts': {for (final e in _parts.entries) e.key: e.value.text.trim()},
              'is_temporary': _temporary,
            });
          },
          child: Text(widget.outfit == null ? 'Add' : 'Save'),
        ),
      ],
    );
  }
}
