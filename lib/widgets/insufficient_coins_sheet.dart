import 'package:flutter/material.dart';
import '../models/insufficient_coins_exception.dart';
import '../screens/mission_screen.dart';
import '../services/rewarded_ad_service.dart';
import '../theme/app_theme.dart';

/// Shown whenever an AiService call throws InsufficientCoinsException —
/// the one place every gated-feature call site routes to, so "not
/// enough coins" always looks and behaves the same everywhere.
Future<void> showInsufficientCoinsSheet(
  BuildContext context,
  InsufficientCoinsException error,
) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _InsufficientCoinsSheet(error: error),
  );
}

class _InsufficientCoinsSheet extends StatefulWidget {
  final InsufficientCoinsException error;
  const _InsufficientCoinsSheet({required this.error});

  @override
  State<_InsufficientCoinsSheet> createState() => _InsufficientCoinsSheetState();
}

class _InsufficientCoinsSheetState extends State<_InsufficientCoinsSheet> {
  bool _watchingAd = false;
  String? _adResultMessage;

  Future<void> _watchAd() async {
    setState(() {
      _watchingAd = true;
      _adResultMessage = null;
    });
    try {
      final coins = await RewardedAdService.showAndClaim();
      if (!mounted) return;
      setState(() {
        _adResultMessage = coins != null
            ? '+$coins coins added! You may still need a few more.'
            : 'No ad available right now — try again in a bit';
      });
    } catch (e) {
      if (mounted) setState(() => _adResultMessage = '$e');
    } finally {
      if (mounted) setState(() => _watchingAd = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = widget.error;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.surfaceBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Not quite enough coins',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            const Text(
              'This one costs a few Viyo Coins to run — complete a mission or check in '
              'today to top up.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.background,
                border: Border.all(color: AppColors.surfaceBorder),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          '${error.balance}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.danger),
                        ),
                        const Text('your balance',
                            style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward, size: 16, color: AppColors.textMuted),
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          '${error.needed}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                        ),
                        const Text('needed',
                            style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: _watchingAd ? null : _watchAd,
              icon: const Icon(Icons.smart_display_outlined, size: 18),
              label: Text(_watchingAd ? 'Loading ad...' : 'Watch an Ad for Coins'),
            ),
            if (_adResultMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                _adResultMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
            ],
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const MissionsScreen()),
                );
              },
              child: const Text('Earn Coins'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Not now', style: TextStyle(color: AppColors.textMuted)),
            ),
          ],
        ),
      ),
    );
  }
}
