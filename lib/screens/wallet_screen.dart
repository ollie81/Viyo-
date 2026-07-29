import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../models/transaction.dart';
import '../../models/user_profile.dart';
import '../../services/coin_service.dart';
import '../../services/profile_service.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/coin_format.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  UserProfile? _profile;
  List<CoinTransaction> _transactions = [];
  bool _loading = true;
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
    if (!mounted) return;
    setState(() {
      _profile = profile;
      _transactions = txs;
      _loading = false;
    });
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
    final amount = double.tryParse(_giftAmountCtrl.text) ?? 0;
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
      final result = await CoinService.giftCoins(
        senderId: userId,
        receiverId: receiver.id,
        amount: amount,
      );
      if (result['success'] == true) {
        _showToast('Gifted $amount coins to @$handle 💜');
        _giftHandleCtrl.clear();
        _load();
      } else {
        _showToast(result['message'] ?? 'Gift failed');
      }
    } finally {
      if (mounted) setState(() => _gifting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: AppColors.background, title: const Text('Wallet')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
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
                        decoration: AppTheme.card(),
                        child: Column(
                          children: [
                            const Text('Your balance', style: TextStyle(color: AppColors.textSecondary)),
                            const SizedBox(height: 6),
                            Text(
                              '${_profile?.pointsBalance ?? 0}',
                              style: const TextStyle(
                                fontSize: 36,
                                fontWeight: FontWeight.bold,
                                color: AppColors.coin,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Streak: ${_profile?.currentStreak ?? 0} days',
                              style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
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
                            const Text('Gift coins to a friend', style: TextStyle(fontWeight: FontWeight.w600)),
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
                            const Text('Recent activity', style: TextStyle(fontWeight: FontWeight.w600)),
                            const SizedBox(height: 12),
                            if (_transactions.isEmpty)
                              const Text('No transactions yet', style: TextStyle(color: AppColors.textMuted))
                            else
                              ..._transactions.map((tx) => Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
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
                if (_toast != null)
                  Positioned(
                    top: 16,
                    left: 40,
                    right: 40,
                    child: Material(
                      color: AppColors.secondary,
                      borderRadius: BorderRadius.circular(30),
                      elevation: 8,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        child: Text(_toast!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
