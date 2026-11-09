import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../../services/creator_studio_service.dart';
import '../../theme/app_theme.dart';

const kStudioContactEmail = 'olli1234x@gmail.com';

String creditsLabel(int n) => '${_group(n)} credit${n == 1 ? '' : 's'}';

String _group(int n) {
  final s = n.abs().toString();
  final b = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

String usdOf(int credits) => '\$${(credits / 100).toStringAsFixed(2)}';

class StudioColors {
  static const panel = Color(0xFF101026);
  static const panelBorder = Color(0xFF23234A);
  static const field = Color(0xFF0E0E22);
}

InputDecoration studioField(String label, {String? hint}) => InputDecoration(
      labelText: label,
      hintText: hint,
      isDense: true,
      filled: true,
      fillColor: StudioColors.field,
      labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
      hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: StudioColors.panelBorder)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: StudioColors.panelBorder)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.primary)),
    );

BoxDecoration studioPanel({Color? border}) => BoxDecoration(
      color: StudioColors.panel,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: border ?? StudioColors.panelBorder),
    );

class CreditPill extends StatelessWidget {
  final StudioBalance balance;
  final VoidCallback? onTap;
  const CreditPill({super.key, required this.balance, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: balance.held > 0 ? '${creditsLabel(balance.held)} reserved for running jobs' : 'Studio credits',
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: AppColors.coin.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.coin.withValues(alpha: 0.35)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.bolt, size: 16, color: AppColors.coin),
            const SizedBox(width: 4),
            Text(_group(balance.available),
                style: const TextStyle(color: AppColors.coin, fontWeight: FontWeight.w700, fontSize: 13,
                    fontFeatures: [FontFeature.tabularFigures()])),
            if (balance.held > 0) ...[
              const SizedBox(width: 6),
              Text('· ${_group(balance.held)} held', style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
            ],
          ]),
        ),
      ),
    );
  }
}

const _kindTitles = {
  'script': 'Write the script',
  'breakdown': 'Break into cast & scenes',
  'lipsync': 'Lip sync',
  'portrait': 'Character portraits',
  'image': 'Scene images',
  'voice': 'Voices',
  'video': 'AI video',
  'render': 'Render the film',
  'outfits': 'Suggest outfits',
};

String kindTitle(String kind) => _kindTitles[kind] ?? kind;

/// Shows the server's price for an action and runs it if the creator agrees.
/// Returns true when jobs were started.
Future<bool> confirmAndRun(
  BuildContext context, {
  required String projectId,
  required String kind,
  List<String> targets = const [],
  String? extraWarning,
  Map<String, dynamic> extra = const {},
  String? title,
  required void Function(StudioBalance) onStarted,
  required VoidCallback onNeedCredits,
}) async {
  StudioEstimate est;
  try {
    est = await CreatorStudioService.estimate(projectId, kind, targets, extra);
  } on StudioException catch (e) {
    if (context.mounted) showStudioError(context, e.message);
    return false;
  }
  if (!context.mounted) return false;
  if (est.readyCount == 0) {
    showStudioError(context, est.blockedReasons.isNotEmpty ? est.blockedReasons.first : 'Nothing to make yet.');
    return false;
  }
  final short = est.totalCredits > est.balance.available;
  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: StudioColors.panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: StudioColors.panelBorder)),
      title: Text(title ?? kindTitle(kind), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          _costRow('Items', '${est.readyCount}${est.items.length > est.readyCount ? ' of ${est.items.length}' : ''}'),
          _costRow('Price', creditsLabel(est.totalCredits), bold: true),
          _costRow('Your balance', creditsLabel(est.balance.available)),
          if (!short) _costRow('After this', creditsLabel(est.balance.available - est.totalCredits)),
          const SizedBox(height: 10),
          Text(
            est.note ?? 'You only pay for what is made. If something fails, the credits come back.',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.4),
          ),
          if (est.items.length > est.readyCount && est.blockedReasons.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Skipped: ${est.blockedReasons.join(' ')}',
                style: const TextStyle(color: AppColors.coin, fontSize: 12, height: 1.4)),
          ],
          if (extraWarning != null) ...[
            const SizedBox(height: 8),
            Text(extraWarning, style: const TextStyle(color: AppColors.coin, fontSize: 12, height: 1.4)),
          ],
          if (short) ...[
            const SizedBox(height: 10),
            Text('You need ${creditsLabel(est.totalCredits - est.balance.available)} more.',
                style: const TextStyle(color: AppColors.danger, fontSize: 13, fontWeight: FontWeight.w600)),
          ],
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        if (short)
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx, false);
              onNeedCredits();
            },
            child: const Text('Get credits'),
          )
        else
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Start · ${creditsLabel(est.totalCredits)}'),
          ),
      ],
    ),
  );
  if (go != true || !context.mounted) return false;
  // A new scene list for a production that has scenes: the creator just saw
  // and accepted the warning in this dialog.
  var confirmReplace = kind == 'breakdown' && extraWarning != null;
  for (var attempt = 0; attempt < 2; attempt++) {
    try {
      final bal = await CreatorStudioService.startJobs(projectId, kind, targets, CreatorStudioService.newRequestId(),
          confirmReplace: confirmReplace, extra: extra);
      onStarted(bal);
      return true;
    } on StudioException catch (e) {
      if (!context.mounted) return false;
      if (e.needsReplaceConfirm && !confirmReplace) {
        final yes = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: StudioColors.panel,
            title: const Text('Replace the scene list?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Text(e.message, style: const TextStyle(height: 1.4))),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Make new scene list')),
            ],
          ),
        );
        if (yes != true || !context.mounted) return false;
        confirmReplace = true;
        continue;
      }
      _startFailed(context, e, onNeedCredits);
      return false;
    }
  }
  return false;
}

void _startFailed(BuildContext context, StudioException e, VoidCallback onNeedCredits) {
  if (e.notEnoughCredits) {
    onNeedCredits();
  } else {
    showStudioError(context, e.message);
  }
}

Widget _costRow(String label, String value, {bool bold = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Expanded(child: Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13))),
        Text(value,
            style: TextStyle(
                fontSize: bold ? 15 : 13,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                color: bold ? AppColors.coin : AppColors.textPrimary,
                fontFeatures: const [FontFeature.tabularFigures()])),
      ]),
    );

void showStudioError(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: const Color(0xFF3A1730)));
}

void showStudioInfo(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

/// Balance, what credits cost and how to get them.
Future<void> showCreditsSheet(BuildContext context) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.background,
    constraints: const BoxConstraints(maxWidth: 640),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
    builder: (_) => const _CreditsSheet(),
  );
}

class _CreditsSheet extends StatefulWidget {
  const _CreditsSheet();
  @override
  State<_CreditsSheet> createState() => _CreditsSheetState();
}

class _CreditsSheetState extends State<_CreditsSheet> {
  StudioAccount? _acct;
  List<Map<String, dynamic>> _history = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final a = await CreatorStudioService.account();
      final (_, h) = await CreatorStudioService.credits();
      if (mounted) {
        setState(() {
          _acct = a;
          _history = h;
        });
      }
    } on StudioException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = _acct;
    return SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        builder: (_, scroll) => ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(20, 14, 20, 24), children: [
          Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          const Text('Studio credits', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text('Credits pay for AI scripts, images, voices, video and rendering. '
              'You see the price before anything starts, and failed work is refunded. '
              'Studio credits are separate from Viyo coins.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4)),
          const SizedBox(height: 16),
          if (_error != null) Text(_error!, style: const TextStyle(color: AppColors.danger)),
          if (a == null && _error == null) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
          if (a != null) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: studioPanel(border: AppColors.coin.withValues(alpha: 0.4)),
              child: Row(children: [
                const Icon(Icons.bolt, color: AppColors.coin, size: 30),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(creditsLabel(a.balance.available), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                    Text(
                        '${_group(a.balance.purchased)} bought · ${_group(a.balance.promotional)} promotional'
                        '${a.balance.held > 0 ? ' · ${_group(a.balance.held)} held for running jobs' : ''}',
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                  ]),
                ),
              ]),
            ),
            const SizedBox(height: 18),
            const Text('Typical prices', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const _PriceGuide(),
            if (kIsWeb) ...[
              const SizedBox(height: 18),
              const Text('Credit packs', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Wrap(spacing: 10, runSpacing: 10, children: [
                for (final p in a.packs)
                  Container(
                    width: 132,
                    padding: const EdgeInsets.all(12),
                    decoration: studioPanel(),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(p.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text('\$${p.priceUsd.toStringAsFixed(2)}', style: const TextStyle(color: AppColors.coin, fontSize: 16, fontWeight: FontWeight.w800)),
                    ]),
                  ),
              ]),
              const SizedBox(height: 10),
              Text(
                a.checkoutAvailable
                    ? 'Choose a pack to pay by card.'
                    : 'Card checkout is opening soon. To buy credits now (mobile money or PayPal), email $kStudioContactEmail '
                        'with your Viyo username and the pack you want.',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.4),
              ),
            ],
            if (_history.isNotEmpty) ...[
              const SizedBox(height: 18),
              const Text('Recent activity', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              for (final h in _history.take(25)) _HistoryRow(h),
            ],
          ],
        ]),
      ),
    );
  }
}

class _PriceGuide extends StatelessWidget {
  const _PriceGuide();
  @override
  Widget build(BuildContext context) {
    const rows = [
      ('Script or scene breakdown', 'about 2–5'),
      ('Character portrait or scene image', 'about 9–12 each'),
      ('Voice for a scene', 'about 1–2'),
      ('AI video for one scene (about 8 s)', 'about 109'),
      ('Render the finished film', 'about 1–3'),
      ('A 1-minute episode with still scenes', 'about 150'),
    ];
    return Container(
      decoration: studioPanel(),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Column(children: [
        for (final (k, v) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(children: [
              Expanded(child: Text(k, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary))),
              Text('$v credits', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ]),
          ),
      ]),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  final Map<String, dynamic> h;
  const _HistoryRow(this.h);
  @override
  Widget build(BuildContext context) {
    final credits = (h['credits'] as num).toInt();
    final label = switch (h['kind']) {
      'purchase' => 'Credits bought',
      'grant' => h['note'] ?? 'Promotional credits',
      'hold' => 'Reserved for a job',
      'release' => 'Returned (unused or failed)',
      'refund' => 'Refund',
      'expire' => 'Expired',
      _ => h['kind'],
    };
    final when = DateTime.tryParse(h['created_at'] ?? '')?.toLocal();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$label', style: const TextStyle(fontSize: 13)),
            if (when != null)
              Text('${when.day}/${when.month}/${when.year} ${when.hour.toString().padLeft(2, '0')}:${when.minute.toString().padLeft(2, '0')}',
                  style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
          ]),
        ),
        Text(credits > 0 ? '+${_group(credits)}' : _group(credits),
            style: TextStyle(fontWeight: FontWeight.w700, color: credits > 0 ? AppColors.success : AppColors.textSecondary)),
      ]),
    );
  }
}

/// A frame with the production's aspect ratio for images and placeholders.
class AspectFrame extends StatelessWidget {
  final bool vertical;
  final String? imageUrl;
  final double width;
  final Widget? overlay;
  final IconData placeholder;
  const AspectFrame({super.key, required this.vertical, this.imageUrl, required this.width, this.overlay, this.placeholder = Icons.image_outlined});

  @override
  Widget build(BuildContext context) {
    final h = vertical ? width * 16 / 9 : width * 9 / 16;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: width,
        height: h,
        color: const Color(0xFF17173A),
        child: Stack(fit: StackFit.expand, children: [
          if (imageUrl != null)
            Image.network(imageUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Icon(placeholder, color: AppColors.textMuted))
          else
            Icon(placeholder, color: AppColors.textMuted, size: 28),
          if (overlay != null) overlay!,
        ]),
      ),
    );
  }
}

// ================================================================ voices

/// The character's voice as a row: name, sound and whether it is in use.
/// Viyo casts voices itself; this shows what it decided and why.
class VoiceTile extends StatelessWidget {
  final StudioVoice? voice;
  final String? voiceName;
  final bool locked;
  final String status;
  final String? ageLabel;
  final int? ageYears;
  final VoidCallback onChange;
  const VoiceTile({
    super.key,
    required this.voice,
    required this.voiceName,
    required this.locked,
    required this.onChange,
    this.status = 'cast',
    this.ageLabel,
    this.ageYears,
  });

  String get _who => ageYears != null ? '$ageYears years old' : (ageLabel ?? '');

  @override
  Widget build(BuildContext context) {
    final note = switch (status) {
      'needs_voice' => 'Viyo doesn\'t have a suitable voice for a ${ageLabel ?? 'character like this'} yet, so '
          'their lines won\'t be voiced. Viyo won\'t use an adult voice instead.',
      'unsupported_language' => 'The voice model doesn\'t speak this production\'s language yet.',
      'approximate' => 'The closest available voice. Viyo has no verified voice for this age yet.',
      _ => null,
    };
    final label = switch (status) {
      'manual' => 'Chosen by you',
      'needs_voice' || 'unsupported_language' => 'No voice yet',
      _ => 'Cast by Viyo',
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      InputDecorator(
        decoration: studioField(_who.isEmpty ? 'Voice' : 'Voice · $_who'),
        child: Row(children: [
          const Icon(Icons.record_voice_over_outlined, size: 18, color: AppColors.textMuted),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                voiceName == null ? 'No voice yet' : '$voiceName${voice == null ? '' : ' · ${voice!.style} · ${voice!.gender}'}',
                overflow: TextOverflow.ellipsis,
              ),
              Text(label, style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
            ]),
          ),
          if (locked)
            const Tooltip(
              message: 'Used in recordings. Changing it affects new and re-recorded lines.',
              child: Padding(padding: EdgeInsets.only(right: 4), child: Icon(Icons.lock_outline, size: 16, color: AppColors.textMuted)),
            ),
          TextButton(onPressed: onChange, child: const Text('Change')),
        ]),
      ),
      if (note != null)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(note, style: const TextStyle(fontSize: 12, color: AppColors.coin, height: 1.35)),
        ),
    ]);
  }
}

/// Lets the creator listen to voices and pick one. Returns the voice name,
/// or null if nothing was chosen.
Future<String?> pickStudioVoice(BuildContext context, List<StudioVoice> voices, String current, String characterName) =>
    showDialog<String>(
      context: context,
      builder: (ctx) => _VoicePicker(voices: voices, current: current, characterName: characterName),
    );

class _VoicePicker extends StatefulWidget {
  final List<StudioVoice> voices;
  final String current, characterName;
  const _VoicePicker({required this.voices, required this.current, required this.characterName});
  @override
  State<_VoicePicker> createState() => _VoicePickerState();
}

class _VoicePickerState extends State<_VoicePicker> {
  late String _chosen = widget.current;
  String _filter = 'all';
  final AudioPlayer _player = AudioPlayer();
  String? _playing;

  @override
  void initState() {
    super.initState();
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playing = null);
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle(StudioVoice v) async {
    if (_playing == v.name) {
      await _player.stop();
      setState(() => _playing = null);
      return;
    }
    setState(() => _playing = v.name);
    try {
      await _player.stop();
      await _player.play(UrlSource(v.sampleUrl!));
    } catch (_) {
      if (mounted) setState(() => _playing = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = widget.voices.where((v) => _filter == 'all' || v.gender == _filter).toList();
    final anySamples = widget.voices.any((v) => v.sampleUrl != null);
    return AlertDialog(
      backgroundColor: StudioColors.panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: StudioColors.panelBorder)),
      title: Text('Voice for ${widget.characterName}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      content: SizedBox(
        width: 460,
        height: MediaQuery.of(context).size.height * 0.6,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SegmentedButton<String>(
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(visualDensity: VisualDensity.compact),
            segments: const [
              ButtonSegment(value: 'all', label: Text('All')),
              ButtonSegment(value: 'female', label: Text('Female')),
              ButtonSegment(value: 'male', label: Text('Male')),
            ],
            selected: {_filter},
            onSelectionChanged: (s) => setState(() => _filter = s.first),
          ),
          const SizedBox(height: 8),
          Text(
            anySamples
                ? 'Tap play to listen. The character keeps this voice in every scene and episode.'
                : 'Samples are coming soon. The character keeps this voice in every scene and episode.',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: ListView.builder(
              itemCount: list.length,
              itemBuilder: (_, i) {
                final v = list[i];
                final selected = v.name == _chosen;
                return ListTile(
                  dense: true,
                  selected: selected,
                  selectedTileColor: AppColors.primary.withValues(alpha: 0.10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  onTap: () => setState(() => _chosen = v.name),
                  leading: Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                      size: 20, color: selected ? AppColors.primary : AppColors.textMuted),
                  title: Text(v.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('${v.style} · ${v.gender}', style: const TextStyle(fontSize: 12)),
                  trailing: v.sampleUrl == null
                      ? null
                      : IconButton(
                          tooltip: _playing == v.name ? 'Stop' : 'Listen',
                          onPressed: () => _toggle(v),
                          icon: Icon(_playing == v.name ? Icons.stop_circle_outlined : Icons.play_circle_outline),
                        ),
                );
              },
            ),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _chosen.isEmpty ? null : () => Navigator.pop(context, _chosen),
          child: Text(_chosen == widget.current ? 'Keep $_chosen' : 'Use $_chosen'),
        ),
      ],
    );
  }
}
