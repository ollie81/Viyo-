import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/insufficient_coins_exception.dart';
import '../../services/glow_up_service.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/friendly_error.dart';
import '../../widgets/guest_gate.dart';
import '../../widgets/insufficient_coins_sheet.dart';
import '../../widgets/xfile_preview_image.dart';
import 'glow_up_history_screen.dart';
import 'glow_up_results_view.dart';
import 'glow_up_session_screen.dart';

/// Viyo Glow Up ✨ — style suggestions from a selfie (Stage 1).
class GlowUpScreen extends StatefulWidget {
  const GlowUpScreen({super.key});

  @override
  State<GlowUpScreen> createState() => _GlowUpScreenState();
}

class _GlowUpScreenState extends State<GlowUpScreen> {
  static const _ageKey = 'glow_up_age_confirmed';
  // Per account, so a shared phone never offers one person's Glow Up to another.
  static String get _lastKey => 'glow_up_last_session_${SupabaseService.currentUserId ?? 'none'}';

  bool _ageConfirmed = false;
  bool _save = true;
  bool _savePhoto = false;          // never on unless the user turns it on
  bool _photoSaved = false;
  String? _lastSessionId;           // reopens the latest saved Glow Up after a refresh
  String _goal = 'everyday';
  String _presentation = 'any';
  XFile? _photo;
  bool _working = false;
  String? _error;
  Map<String, dynamic>? _result;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (mounted) {
        setState(() {
          _ageConfirmed = p.getBool(_ageKey) ?? false;
          _lastSessionId = p.getString(_lastKey);
        });
      }
    }).catchError((_) {});
  }

  Future<void> _setAge(bool v) async {
    setState(() => _ageConfirmed = v);
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_ageKey, v);
    } catch (_) {}
  }

  Future<void> _pick(ImageSource source) async {
    try {
      final file = await ImagePicker().pickImage(
        source: source,
        preferredCameraDevice: CameraDevice.front,
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 88,
      );
      if (file != null && mounted) {
        setState(() {
          _photo = file;
          _error = null;
          _result = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not open the photo: ${friendlyErrorMessage(e)}');
    }
  }

  Future<void> _run() async {
    final photo = _photo;
    if (photo == null || !_ageConfirmed) return;
    if (!await GuestGate.allow(context, action: 'use Glow Up')) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final bytes = await photo.readAsBytes();
      final res = await GlowUpService.analyze(
        imageBytes: bytes,
        ageConfirmed: _ageConfirmed,
        styleGoal: _goal,
        presentation: _presentation,
        save: _save,
        savePhoto: _savePhoto,
      );
      if (!mounted) return;
      final sessionId = res['session_id'] as String?;
      setState(() {
        _result = res['result'] as Map<String, dynamic>?;
        _saved = res['saved'] == true;
        _photoSaved = res['photo_saved'] == true;
        if (sessionId != null) _lastSessionId = sessionId;
      });
      if (sessionId != null) {
        try {
          final p = await SharedPreferences.getInstance();
          await p.setString(_lastKey, sessionId);
        } catch (_) {}
      }
    } on InsufficientCoinsException catch (e) {
      if (mounted) showInsufficientCoinsSheet(context, e);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyErrorMessage(e));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _startOver() => setState(() {
        _photo = null;
        _result = null;
        _error = null;
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Glow Up ✨'),
        actions: [
          IconButton(
            tooltip: 'My Glow Ups',
            icon: const Icon(Icons.history),
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const GlowUpHistoryScreen())),
          ),
        ],
      ),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: _result != null ? _resultsPage() : _setupPage(),
        ),
      ),
    );
  }

  Widget _resultsPage() {
    return ListView(
      key: const ValueKey('results'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        GlowUpPhotoHeader(
          photo: _photo != null ? XFilePreviewImage(file: _photo!) : null,
          caption: _photoSaved
              ? 'Saved privately with this Glow Up. Only you can see it, and you can delete it any time.'
              : 'Not saved. It stays on this screen until you leave, then it\'s gone.',
          details: [
            GlowUpService.styleGoals[_goal] ?? '',
            if (_presentation != 'any') GlowUpService.presentations[_presentation] ?? '',
            'Today',
          ].where((x) => x.isNotEmpty).join(' · '),
        ),
        const SizedBox(height: 16),
        GlowUpResultsView(result: _result!),
        const SizedBox(height: 16),
        Text(
          _saved
              ? 'Ideas saved to My Glow Ups${_photoSaved ? ' with your photo' : ''}.'
              : 'Ideas not saved.',
          style: TextStyle(fontSize: 11.5, color: _saved ? AppColors.success : AppColors.textMuted),
        ),
        const SizedBox(height: 14),
        ElevatedButton.icon(
          onPressed: _startOver,
          icon: const Icon(Icons.refresh),
          label: const Text('Try another photo'),
        ),
      ],
    );
  }

  Widget _setupPage() {
    final canRun = _photo != null && _ageConfirmed && !_working;
    return ListView(
      key: const ValueKey('setup'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: AppTheme.glowCard(glowColor: AppColors.secondary, gradient: AppGradients.primary, glowOpacity: 0.22),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Your personal style ideas',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              SizedBox(height: 6),
              Text('Upload a selfie and get hairstyle, grooming, style and colour ideas picked for you.',
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4)),
              SizedBox(height: 12),
              _Promise(icon: Icons.lock_outline, text: 'Your photo is only saved if you choose. Never public.'),
              _Promise(icon: Icons.favorite_border, text: 'Ideas to try. No ratings, no scores, no judgments.'),
              _Promise(icon: Icons.delete_outline, text: 'Delete saved ideas and photos any time.'),
            ],
          ),
        ),
        if (_lastSessionId != null) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () async {
              final deleted = await Navigator.of(context).push<bool>(MaterialPageRoute(
                builder: (_) => GlowUpSessionScreen(sessionId: _lastSessionId!),
              ));
              if (deleted == true && mounted) {
                setState(() => _lastSessionId = null);
                try {
                  final p = await SharedPreferences.getInstance();
                  await p.remove(_lastKey);
                } catch (_) {}
              }
            },
            icon: const Icon(Icons.history, size: 18),
            label: const Text('Open my latest Glow Up'),
          ),
        ],
        const SizedBox(height: 16),
        _photoPicker(),
        const SizedBox(height: 16),
        const Text('The look you want', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        _chips(GlowUpService.styleGoals, _goal, (v) => setState(() => _goal = v)),
        const SizedBox(height: 14),
        const Text('Style direction', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        _chips(GlowUpService.presentations, _presentation, (v) => setState(() => _presentation = v)),
        const SizedBox(height: 14),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _save || _savePhoto,
          activeColor: AppColors.primary,
          onChanged: _savePhoto ? null : (v) => setState(() => _save = v),
          title: const Text('Save my ideas to My Glow Ups', style: TextStyle(fontSize: 13.5)),
          subtitle: const Text('Your ideas, the look you chose and the date, so you can reopen them later.',
              style: TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _savePhoto,
          activeColor: AppColors.primary,
          onChanged: (v) => setState(() => _savePhoto = v),
          title: const Text('Also save my photo (optional)', style: TextStyle(fontSize: 13.5)),
          subtitle: const Text(
              'Off by default. If on, your photo is kept privately with this Glow Up. Only you can see it, '
              'it\'s never public, and you can delete it any time.',
              style: TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _ageConfirmed,
          activeColor: AppColors.primary,
          onChanged: (v) => _setAge(v ?? false),
          title: const Text("I'm 18 or older", style: TextStyle(fontSize: 13.5)),
          subtitle: const Text('Glow Up is for adults only.',
              style: TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
        ),
        if (_error != null) ...[
          const SizedBox(height: 6),
          Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
        ],
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: canRun ? _run : null,
          child: Text(_working ? 'Looking at your style…' : 'Get my Glow Up · ${GlowUpService.costCoins} coins'),
        ),
        if (_working)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: LinearProgressIndicator(minHeight: 3),
          ),
        const SizedBox(height: 10),
        const Text(
          "You're only charged if we can create your ideas. If something goes wrong, your coins are refunded.",
          style: TextStyle(fontSize: 11, color: AppColors.textMuted, height: 1.4),
        ),
      ],
    );
  }

  Widget _photoPicker() {
    final photo = _photo;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.card(),
      child: Column(
        children: [
          if (photo != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(height: 240, width: 180, child: XFilePreviewImage(file: photo)),
            )
          else
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Column(children: [
                Icon(Icons.face_retouching_natural, size: 44, color: AppColors.primary),
                SizedBox(height: 8),
                Text('A clear, front-facing selfie in good light works best.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
              ]),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _working ? null : () => _pick(ImageSource.camera),
                  icon: const Icon(Icons.photo_camera_front, size: 18),
                  label: const Text('Take selfie'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _working ? null : () => _pick(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined, size: 18),
                  label: const Text('Choose photo'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chips(Map<String, String> options, String selected, ValueChanged<String> onPick) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.entries.map((e) {
        final on = e.key == selected;
        return ChoiceChip(
          label: Text(e.value),
          selected: on,
          onSelected: _working ? null : (_) => onPick(e.key),
          selectedColor: AppColors.primary.withOpacity(0.18),
          backgroundColor: AppColors.surface,
          labelStyle: TextStyle(
            fontSize: 12.5,
            color: on ? AppColors.primary : AppColors.textSecondary,
            fontWeight: on ? FontWeight.w700 : FontWeight.w500,
          ),
          side: BorderSide(color: on ? AppColors.primary : AppColors.surfaceBorder),
        );
      }).toList(),
    );
  }
}

class _Promise extends StatelessWidget {
  final IconData icon;
  final String text;

  const _Promise({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(children: [
          Icon(icon, size: 15, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12.5))),
        ]),
      );
}
