import 'package:flutter/material.dart';
import '../../../models/ad_hook.dart';
import '../../../services/ads_studio_service.dart';
import '../../../theme/app_theme.dart';
import 'ads_script_screen.dart';

/// The Hook-First Engine's own screen — generates 5 distinct opening-
/// hook candidates, each scored transparently on 5 dimensions (see
/// ads_studio.py's HOOK_SCORE_WEIGHTS for the exact weighting), and lets
/// the admin preview and pick one, or auto-pick whichever ranked #1.
/// Nothing past this screen runs until a hook is actually selected.
class AdsHookScreen extends StatefulWidget {
  final String adminKey;
  final String campaignId;
  const AdsHookScreen({super.key, required this.adminKey, required this.campaignId});

  @override
  State<AdsHookScreen> createState() => _AdsHookScreenState();
}

class _AdsHookScreenState extends State<AdsHookScreen> {
  bool _loading = true;
  bool _generating = false;
  bool _selecting = false;
  String? _error;
  List<AdHook> _hooks = [];
  String? _recommendedFormat;
  String? _selectedHookId;

  @override
  void initState() {
    super.initState();
    _loadOrGenerate();
  }

  Future<void> _loadOrGenerate() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final existing = await AdsStudioService.listHooks(widget.adminKey, widget.campaignId);
      if (existing.isNotEmpty) {
        AdHook? selected;
        for (final h in existing) {
          if (h.selected) selected = h;
        }
        setState(() {
          _hooks = existing;
          _selectedHookId = selected?.id;
        });
      } else {
        await _generate();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _generate() async {
    setState(() {
      _generating = true;
      _error = null;
    });
    try {
      final result = await AdsStudioService.generateHooks(widget.adminKey, widget.campaignId);
      if (!mounted) return;
      setState(() {
        _hooks = result.hooks;
        _recommendedFormat = result.recommendedFormat;
        _selectedHookId = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), ''));
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _select(String hookId) async {
    setState(() => _selecting = true);
    try {
      final updated = await AdsStudioService.selectHook(widget.adminKey, widget.campaignId, hookId);
      if (!mounted) return;
      setState(() => _selectedHookId = updated.selectedHookId);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst(RegExp(r'^Exception:\s*'), ''))));
    } finally {
      if (mounted) setState(() => _selecting = false);
    }
  }

  void _continue() {
    if (_selectedHookId == null) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => AdsScriptScreen(adminKey: widget.adminKey, campaignId: widget.campaignId),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: const Text('Choose a hook'),
        actions: [
          IconButton(
            tooltip: 'Generate 5 new hooks',
            icon: const Icon(Icons.refresh),
            onPressed: _generating ? null : _generate,
          ),
        ],
      ),
      body: _loading || _generating
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(_error!, style: const TextStyle(color: AppColors.danger), textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      ElevatedButton(onPressed: _generate, child: const Text('Retry')),
                    ]),
                  ),
                )
              : _content(),
      bottomNavigationBar: _loading || _generating || _error != null || _hooks.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _selecting ? null : () => _select('auto'),
                        child: const Text('Auto-pick top'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _selectedHookId == null ? null : _continue,
                        child: const Text('Continue'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _content() {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          color: AppColors.surface,
          child: Text(
            'Scores are a relative ranking signal from a weighted rubric — not a guarantee of real performance. '
            '${_recommendedFormat != null ? "Gemini's recommended format: $_recommendedFormat." : ""}',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
            children: _hooks.map((h) => Padding(padding: const EdgeInsets.only(bottom: 10), child: _hookCard(h))).toList(),
          ),
        ),
      ],
    );
  }

  Widget _hookCard(AdHook h) {
    final selected = h.id == _selectedHookId;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.card(borderColor: selected ? AppColors.primary : null),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: AppColors.coin.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
                child: Text('#${h.rank} · ${h.scoreTotal.toStringAsFixed(1)}', style: const TextStyle(color: AppColors.coin, fontSize: 11, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 8),
              Text(h.angle, style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 8),
          Text(h.hookText, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
          const SizedBox(height: 6),
          Text(h.rationale, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _scorePill('Attention', h.scoreAttention),
              _scorePill('Curiosity', h.scoreCuriosity),
              _scorePill('Emotional', h.scoreEmotional),
              _scorePill('Relevance', h.scoreRelevance),
              _scorePill('Transition', h.scoreTransition),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _selecting ? null : () => _select(h.id),
              style: selected ? OutlinedButton.styleFrom(backgroundColor: AppColors.primary.withOpacity(0.12)) : null,
              child: Text(selected ? 'Selected' : 'Choose this hook'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _scorePill(String label, int score) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.surfaceBorder)),
      child: Text('$label $score', style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted)),
    );
  }
}
