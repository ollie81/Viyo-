import 'package:flutter/material.dart';

import '../../services/creator_studio_service.dart';
import '../../theme/app_theme.dart';
import 'studio_widgets.dart';

/// The look of the film: one visual identity for every picture and clip. Free to view and edit.
class StudioLookCard extends StatefulWidget {
  final String projectId;
  final Future<Map<String, dynamic>> Function(String id)? load;
  final Future<Map<String, dynamic>> Function(String id, Map<String, dynamic> fields, {bool reset})? save;
  const StudioLookCard({super.key, required this.projectId, this.load, this.save});

  @override
  State<StudioLookCard> createState() => _StudioLookCardState();
}

class _StudioLookCardState extends State<StudioLookCard> {
  Map<String, dynamic>? state;
  bool busy = false;

  static const lists = {'palette', 'avoid'};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await (widget.load ?? CreatorStudioService.look)(widget.projectId);
      if (mounted) setState(() => state = s);
    } catch (_) {}
  }

  String _text(Object? v) => v is List ? v.join(', ') : '${v ?? ''}';

  Future<void> _save(Map<String, dynamic> fields, {bool reset = false}) async {
    setState(() => busy = true);
    try {
      final save = widget.save ?? CreatorStudioService.saveLook;
      final s = await save(widget.projectId, fields, reset: reset);
      if (mounted) setState(() => state = s);
    } catch (e) {
      if (mounted) showStudioError(context, '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _edit() async {
    final look = Map<String, dynamic>.from(state!['look'] as Map);
    final fields = ((state!['fields'] as List?) ?? const []).map((e) => '$e').toList();
    final labels = Map<String, dynamic>.from(state!['labels'] as Map? ?? const {});
    final ctrl = {for (final f in ['style', ...fields]) f: TextEditingController(text: _text(look[f]))};
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: StudioColors.panel,
        title: const Text('Look of the film'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              for (final f in ['style', ...fields])
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextField(
                    controller: ctrl[f],
                    maxLines: null,
                    decoration: InputDecoration(
                      labelText: f == 'style' ? 'Your style' : '${labels[f] ?? f}',
                      helperText: lists.contains(f) ? 'Separate with commas' : null,
                    ),
                  ),
                ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save look')),
        ],
      ),
    );
    if (ok != true) return;
    final changed = <String, dynamic>{};
    ctrl.forEach((f, c) {
      if (c.text.trim() != _text(look[f]).trim()) {
        changed[f] = lists.contains(f) ? c.text.split(',').map((x) => x.trim()).where((x) => x.isNotEmpty).toList() : c.text.trim();
      }
    });
    if (changed.isNotEmpty) await _save(changed);
  }

  @override
  Widget build(BuildContext context) {
    final s = state;
    if (s == null) return const SizedBox.shrink();
    final look = Map<String, dynamic>.from(s['look'] as Map? ?? const {});
    final fields = ((s['fields'] as List?) ?? const []).map((e) => '$e').toList();
    final labels = Map<String, dynamic>.from(s['labels'] as Map? ?? const {});
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        const Icon(Icons.camera_outlined, size: 18, color: AppColors.coin),
        const SizedBox(width: 8),
        const Expanded(child: Text('Look of the film', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5))),
        Text(s['saved'] == true ? (look['source'] == 'creator' ? 'Yours' : 'Saved') : 'Proposed',
            style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
      ]),
      const SizedBox(height: 4),
      Text('${s['note'] ?? ''}',
          style: TextStyle(fontSize: 12, color: s['applies'] == true ? AppColors.textMuted : AppColors.coin)),
      const SizedBox(height: 8),
      if ((look['style'] ?? '').toString().isNotEmpty) _row('Your style', _text(look['style'])),
      for (final f in fields)
        if (_text(look[f]).isNotEmpty) _row('${labels[f] ?? f}', _text(look[f])),
      const SizedBox(height: 6),
      Wrap(spacing: 8, runSpacing: 8, children: [
        OutlinedButton.icon(
            onPressed: busy ? null : _edit, icon: const Icon(Icons.edit, size: 16), label: const Text('Edit look')),
        if (look['source'] == 'creator')
          TextButton(onPressed: busy ? null : () => _save({}, reset: true), child: const Text('Use VIYO\'s proposal')),
      ]),
    ]);
  }

  Widget _row(String a, String b) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text.rich(TextSpan(children: [
          TextSpan(text: '$a: ', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
          TextSpan(text: b, style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
        ])),
      );
}
