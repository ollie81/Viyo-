import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../models/transaction.dart';
import '../models/user_profile.dart';
import '../services/coin_service.dart';
import '../services/profile_service.dart';
import '../services/rewarded_ad_service.dart';
import '../services/supabase_service.dart';
import '../services/wallet_service.dart';
import '../theme/app_theme.dart';
import '../utils/coin_format.dart';
import '../widgets/viyo_toast.dart';
import 'wallet/buy_coins_screen.dart';
import 'wallet/subscribe_screen.dart';
import 'wallet/payout_settings_screen.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  UserProfile? _profile;
  List<CoinTransaction> _transactions = [];
  WalletEarnings _earnings = WalletEarnings.empty();
  bool _loading = true;
  bool _withdrawing = false;
  bool _watchingAd = false;
  final _giftHandleCtrl = TextEditingController();
  final _giftAmountCtrl = TextEditingController(text: '50');
  bool _gifting = false;
  String? _toast;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final userId = SupabaseService.currentUserId;
    if (userId == null) return;
    setState(() => _loading = true);
    final profile = await ProfileService.getProfile(userId);
    final txs = await CoinService.getTransactions(userId);
    // Best-effort — a creator with no AI Short Drama earnings yet
    // (or a backend hiccup) shouldn't block the rest of the wallet.
    final earnings = await WalletService.getEarnings().catchError((_) => WalletEarnings.empty());
    if (!mounted) return;
    setState(() {
      _profile = profile;
      _transactions = txs;
      _earnings = earnings;
      _loading = false;
    });
  }

  Future<void> _editPayoutDetails() async {
    final saved = await Navigator.of(context).push<PayoutSettings>(
      MaterialPageRoute(builder: (_) => PayoutSettingsScreen(current: _earnings.payoutSettings)),
    );
    if (saved != null) {
      _showToast('Payout details saved');
      _load();
    }
  }

  Future<void> _requestWithdrawal() async {
    if (_earnings.payoutSettings == null) return _editPayoutDetails();
    setState(() => _withdrawing = true);
    try {
      final usd = await WalletService.requestWithdrawal();
      _showToast('Withdrawal of \$${usd.toStringAsFixed(2)} requested. We\'ll send it soon 💸');
      _load();
    } catch (e) {
      _showToast('$e');
    } finally {
      if (mounted) setState(() => _withdrawing = false);
    }
  }

  Future<void> _watchAdForCoins() async {
    setState(() => _watchingAd = true);
    try {
      final coins = await RewardedAdService.showAndClaim();
      if (coins != null) {
        _showToast('+$coins coins — thanks for watching! 🎬');
        _load();
      } else {
        _showToast('No ad available right now — try again in a bit');
      }
    } catch (e) {
      _showToast('$e');
    } finally {
      if (mounted) setState(() => _watchingAd = false);
    }
  }

  void _showToast(String msg) {
    setState(() => _toast = msg);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _toast = null);
    });
  }

  Future<void> _sendGift() async {
    final userId = SupabaseService.currentUserId;
    final handle = _giftHandleCtrl.text.trim().replaceFirst('@', '');
    final amount = double.tryParse(_giftAmountCtrl.text)?.round() ?? 0;
    if (userId == null || handle.isEmpty || amount < 10) {
      _showToast('Enter a username and at least 10 coins');
      return;
    }

    setState(() => _gifting = true);
    try {
      final receiver = await ProfileService.getProfileByUsername(handle);
      if (receiver == null) {
        _showToast('User @$handle not found');
        return;
      }
      await CoinService.giftCoins(
        senderId: userId,
        receiverId: receiver.id,
        amount: amount,
      );
      _showToast('Gifted $amount coins to @$handle 💜');
      _giftHandleCtrl.clear();
      _load();
    } catch (e) {
      _showToast('$e');
    } finally {
      if (mounted) setState(() => _gifting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: AppColors.background, title: const Text('Wallet')),
      body: _loading
          ? const _WalletSkeleton()
          : Stack(
              children: [
                RefreshIndicator(
                  onRefresh: _load,
                  color: AppColors.primary,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: AppTheme.glowCard(glowColor: AppColors.coin, glowOpacity: 0.2),
                        child: Column(
                          children: [
                            const Text('Your balance', style: TextStyle(color: AppColors.textSecondary)),
                            const SizedBox(height: 6),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    gradient: AppGradients.coin,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.monetization_on_rounded, color: AppColors.background, size: 22),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  '${_profile?.pointsBalance ?? 0}',
                                  style: const TextStyle(
                                    fontSize: 36,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.coin,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Streak: ${_profile?.currentStreak ?? 0} days',
                              style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: () async {
                                  final purchased = await Navigator.of(context).push<bool>(
                                    MaterialPageRoute(builder: (_) => const BuyCoinsScreen()),
                                  );
                                  if (purchased == true) _load();
                                },
                                icon: const Icon(Icons.add_circle_outline, size: 18),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.coin,
                                  foregroundColor: AppColors.background,
                                ),
                                label: const Text('Buy Coins'),
                              ),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: _watchingAd ? null : _watchAdForCoins,
                                icon: const Icon(Icons.smart_display_outlined, size: 18),
                                label: Text(_watchingAd ? 'Loading ad...' : 'Watch Ad for Free Coins'),
                              ),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: () => Navigator.of(context).push(
                                  MaterialPageRoute(builder: (_) => const SubscribeScreen()),
                                ),
                                icon: const Icon(Icons.workspace_premium_outlined, size: 18),
                                label: const Text('Go Premium — Unlimited Episodes'),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_earnings.lifetimeCoins > 0) ...[
                        const SizedBox(height: 14),
                        _EarningsCard(
                          earnings: _earnings,
                          withdrawing: _withdrawing,
                          onWithdraw: _requestWithdrawal,
                          onEditPayout: _editPayoutDetails,
                        ),
                      ],
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: AppTheme.card(),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.card_giftcard_rounded, size: 15, color: AppColors.secondary),
                                SizedBox(width: 6),
                                Text('Gift coins to a friend', style: TextStyle(fontWeight: FontWeight.w600)),
                              ],
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _giftHandleCtrl,
                              style: const TextStyle(color: Colors.white),
                              decoration: const InputDecoration(hintText: '@username'),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                SizedBox(
                                  width: 90,
                                  child: TextField(
                                    controller: _giftAmountCtrl,
                                    keyboardType: TextInputType.number,
                                    style: const TextStyle(color: Colors.white),
                                    decoration: const InputDecoration(hintText: '50'),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: _gifting ? null : _sendGift,
                                    child: Text(_gifting ? 'Sending...' : 'Send Gift 💜'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: AppTheme.card(),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.receipt_long_rounded, size: 15, color: AppColors.secondary),
                                SizedBox(width: 6),
                                Text('Recent activity', style: TextStyle(fontWeight: FontWeight.w600)),
                              ],
                            ),
                            const SizedBox(height: 12),
                            if (_transactions.isEmpty)
                              const Text('No transactions yet', style: TextStyle(color: AppColors.textMuted))
                            else
                              ..._transactions.map((tx) => Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 32,
                                          height: 32,
                                          decoration: BoxDecoration(
                                            color: (tx.isEarn ? AppColors.success : Colors.white38)
                                                .withOpacity(0.14),
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: Icon(
                                            tx.isEarn ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                                            size: 16,
                                            color: tx.isEarn ? AppColors.success : Colors.white54,
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(tx.description,
                                                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
                                              Text(timeago.format(tx.createdAt),
                                                  style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                                            ],
                                          ),
                                        ),
                                        Text(
                                          '${tx.isEarn ? '+' : ''}${formatCoins(tx.amount)}',
                                          style: TextStyle(
                                            color: tx.isEarn ? AppColors.success : Colors.white54,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (_toast != null) ViyoToast(message: _toast!),
              ],
            ),
    );
  }
}

/// Earnings from AI Short Drama episode unlocks — a separate balance
/// from the coins above, since these are real money owed to the
/// creator (65% of every locked-episode unlock) rather than in-app
/// currency they can spend, so "withdraw" means something different
/// here than "buy coins" does above it.
class _EarningsCard extends StatelessWidget {
  final WalletEarnings earnings;
  final bool withdrawing;
  final VoidCallback onWithdraw;
  final VoidCallback onEditPayout;

  const _EarningsCard({
    required this.earnings,
    required this.withdrawing,
    required this.onWithdraw,
    required this.onEditPayout,
  });

  static String _usd(double v) => '\$${v.toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    final e = earnings;
    final settings = e.payoutSettings;
    final enough = e.availableCoins >= e.minWithdrawalCoins;
    String label;
    if (withdrawing) {
      label = 'Requesting...';
    } else if (e.pendingRequestUsd != null) {
      label = 'Withdrawal on its way';
    } else if (settings == null) {
      label = 'Add payout details';
    } else if (enough) {
      label = 'Withdraw ${_usd(e.availableUsd)}';
    } else {
      label = 'Withdraw from ${_usd(e.minWithdrawalUsd)}';
    }
    final canTap = !withdrawing && e.pendingRequestUsd == null && (settings == null || enough);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.card(borderColor: AppColors.secondary.withValues(alpha: 0.35)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.auto_awesome, size: 15, color: AppColors.secondary),
              SizedBox(width: 6),
              Text('Creator earnings', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _EarningsStat(label: 'Available', usd: e.availableUsd, coins: e.availableCoins, color: AppColors.success)),
              Expanded(child: _EarningsStat(label: 'Pending', usd: e.pendingWithdrawalUsd, coins: e.pendingWithdrawalCoins, color: AppColors.coin)),
              Expanded(child: _EarningsStat(label: 'Paid out', usd: e.paidUsd, coins: e.paidCoins, color: AppColors.textSecondary)),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'You earn 65% of the coins viewers buy and spend on your titles. 1 coin = \$${e.coinUsd}. '
            'Withdraw from ${_usd(e.minWithdrawalUsd)}.',
            style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
          if (e.pendingRequestUsd != null) ...[
            const SizedBox(height: 10),
            Text(
              '${_usd(e.pendingRequestUsd!)} is on its way to ${e.pendingRequestDestination ?? 'you'}.',
              style: const TextStyle(fontSize: 12, color: AppColors.coin, fontWeight: FontWeight.w600),
            ),
          ],
          const SizedBox(height: 12),
          InkWell(
            onTap: onEditPayout,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  const Icon(Icons.payments_outlined, size: 16, color: AppColors.textSecondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      settings == null ? 'No payout details yet' : 'Paid to ${settings.summary}',
                      style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(settings == null ? 'Add' : 'Change',
                      style: const TextStyle(fontSize: 12.5, color: AppColors.primary, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: canTap ? onWithdraw : null,
              child: Text(label),
            ),
          ),
        ],
      ),
    );
  }
}

class _EarningsStat extends StatelessWidget {
  final String label;
  final double usd;
  final int coins;
  final Color color;
  const _EarningsStat({required this.label, required this.usd, required this.coins, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('\$${usd.toStringAsFixed(2)}', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: color)),
        const SizedBox(height: 2),
        Text('$label · ${formatCoins(coins)} coins', style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted)),
      ],
    );
  }
}

/// Shown while wallet balance/transactions are loading — mimics the real
/// layout instead of a bare spinner.
class _WalletSkeleton extends StatelessWidget {
  const _WalletSkeleton();

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppColors.surface,
      highlightColor: AppColors.surfaceBorder,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
        physics: const NeverScrollableScrollPhysics(),
        children: [
          Container(
            height: 140,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
          ),
          const SizedBox(height: 14),
          Container(
            height: 150,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
          ),
          const SizedBox(height: 14),
          Container(
            height: 180,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
          ),
        ],
      ),
    );
  }
}
