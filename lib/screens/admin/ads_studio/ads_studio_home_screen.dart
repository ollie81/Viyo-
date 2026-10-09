import 'package:flutter/material.dart';
import '../../../models/ad_campaign.dart';
import '../../../services/ads_studio_service.dart';
import '../../../services/supabase_service.dart';
import '../../../theme/app_theme.dart';
import 'ads_studio_wizard_screen.dart';
import 'ads_result_screen.dart';

/// AI Ads Studio's entry point — lists every campaign with its current
/// stage, same list-then-drill-in shape as ViyoStudioHomeScreen. Reached
/// from Settings' "Admin Tools" sheet.
class AdsStudioHomeScreen extends StatefulWidget {
  const AdsStudioHomeScreen({super.key});

  @override
  State<AdsStudioHomeScreen> createState() => _AdsStudioHomeScreenState();
}

class _AdsStudioHomeScreenState extends State<AdsStudioHomeScreen> {
  final _keyController = TextEditingController();
  String? _adminKey;
  String? _unlockError;

  bool _loading = false;
  String? _error;
  List<AdCampaign> _campaigns = [];

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  void _unlock() {
    final key = _keyController.text.trim();
    if (key.isEmpty) return;
    setState(() {
      _adminKey = key;
      _unlockError = null;
    });
    _load();
  }

  Future<void> _load() async {
    final adminKey = _adminKey;
    if (adminKey == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final campaigns = await AdsStudioService.listCampaigns(adminKey);
      if (!mounted) return;
      setState(() => _campaigns = campaigns);
    } catch (e) {
      if (!mounted) return;
      final message = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
      if (message.contains('Invalid admin key')) {
        setState(() {
          _adminKey = null;
          _unlockError = message;
        });
      } else {
        setState(() => _error = message);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _newCampaign() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => AdsStudioWizardScreen(adminKey: _adminKey!)))
        .then((_) => _load());
  }

  void _openCampaign(AdCampaign c) {
    Navigator.of(context)
        .push(MaterialPageRoute(
          builder: (_) => AdsStudioWizardScreen(adminKey: _adminKey!, preselectedCampaignId: c.id),
        ))
        .then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: AppColors.background, title: const Text('AI Ads Studio')),
      body: SupabaseService.isGuest ? _guestBlock() : (_adminKey == null ? _keyPrompt() : _content()),
    );
  }

  // Same reasoning as ViyoStudioHomeScreen's own guest block: a campaign
  // created while signed in as a guest would be owned by a disposable
  // account with nothing recoverable if that session ever expires.
  Widget _guestBlock() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 40, color: AppColors.textMuted),
            SizedBox(height: 16),
            Text('Log into a real account first', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15), textAlign: TextAlign.center),
            SizedBox(height: 8),
            Text(
              "You're browsing as a guest. Log in or create an account from the Profile tab, then come back here.",
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _keyPrompt() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.campaign_outlined, size: 40, color: AppColors.textMuted),
            const SizedBox(height: 16),
            TextField(
              controller: _keyController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Admin key'),
              onSubmitted: (_) => _unlock(),
            ),
            const SizedBox(height: 14),
            SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _unlock, child: const Text('Unlock'))),
            if (_unlockError != null) ...[
              const SizedBox(height: 12),
              Text(_unlockError!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _content() {
    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.primary,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _newCampaign,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('New Campaign'),
            ),
          ),
          const SizedBox(height: 18),
          if (_loading)
            const Padding(padding: EdgeInsets.only(top: 40), child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 40),
              child: Center(
                child: Column(
                  children: [
                    Text(_error!, style: const TextStyle(color: AppColors.danger), textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    ElevatedButton(onPressed: _load, child: const Text('Retry')),
                  ],
                ),
              ),
            )
          else if (_campaigns.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 40),
              child: Center(child: Text('No campaigns yet.', style: TextStyle(color: AppColors.textMuted))),
            )
          else
            ..._campaigns.map((c) => Padding(padding: const EdgeInsets.only(bottom: 10), child: _campaignCard(c))),
        ],
      ),
    );
  }

  Widget _campaignCard(AdCampaign c) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => c.status == 'ready' || c.status == 'failed'
          ? Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => AdsResultScreen(adminKey: _adminKey!, campaignId: c.id)))
              .then((_) => _load())
          : _openCampaign(c),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: AppTheme.card(),
        child: Row(
          children: [
            if (c.thumbnailUrl != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(c.thumbnailUrl!, width: 48, height: 48, fit: BoxFit.cover),
              )
            else
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.campaign_outlined, color: AppColors.textMuted, size: 20),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.targetName.isEmpty ? '(untitled campaign)' : c.targetName,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${c.promoteTarget} · ${c.format ?? 'no format yet'} · ${c.durationSeconds}s · ${c.aspectRatio}',
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            _statusChip(c.status),
          ],
        ),
      ),
    );
  }

  Widget _statusChip(String status) {
    final color = switch (status) {
      'ready' => AppColors.success,
      'failed' => AppColors.danger,
      'generating' => AppColors.coin,
      _ => AppColors.textMuted,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(status, style: TextStyle(fontSize: 11, color: color)),
    );
  }
}
