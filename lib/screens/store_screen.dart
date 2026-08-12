import 'package:flutter/material.dart';
import '../models/app_badge.dart';
import '../models/user_profile.dart';
import '../services/coin_service.dart';
import '../services/profile_service.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/coin_badge.dart';

class StoreScreen extends StatefulWidget {
  const StoreScreen({super.key});

  @override
  State<StoreScreen> createState() => _StoreScreenState();
}

class _StoreScreenState extends State<StoreScreen> {
  List<AppBadge> _badges = [];
  UserProfile? _profile;
  bool _loading = true;
  bool _purchasingPremium = false;
  String? _toast;

  static const double _premiumCost = 500;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final userId = SupabaseService.currentUserId;
    if (userId == null) return;
    setState(() => _loading = true);
    final badges = await CoinService.getStoreBadges(userId);
    final profile = await ProfileService.getProfile(userId);
    if (!mounted) return;
    setState(() {
      _badges = badges;
      _profile = profile;
      _loading = false;
    });
  }

  Future<void> _purchasePremium() async {
    final userId = SupabaseService.currentUserId;
    if (userId == null) return;
    setState(() => _purchasingPremium = true);
    try {
      final result = await ProfileService.purchasePremium(userId: userId, cost: _premiumCost);
      if (result['success'] == true) {
        _showToast('Welcome to Premium! ✓');
        _load();
      } else {
        _showToast(result['message'] ?? 'Purchase failed');
      }
    } catch (e) {
      _showToast('Purchase failed: $e');
    } finally {
      if (mounted) setState(() => _purchasingPremium = false);
    }
  }

  void _showToast(String msg) {
    setState(() => _toast = msg);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _toast = null);
    });
  }

  Future<void> _purchase(AppBadge badge) async {
    final userId = SupabaseService.currentUserId;
    if (userId == null) return;
    final result = await CoinService.purchaseBadge(userId: userId, badgeId: badge.id);
    if (result['success'] == true) {
      _showToast('Unlocked: ${badge.name}!');
      _load();
    } else {
      _showToast(result['message'] ?? 'Purchase failed');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: AppColors.background, title: const Text('Store')),
      body: Stack(
        children: [
          _loading
              ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
              : RefreshIndicator(
                  onRefresh: _load,
                  color: AppColors.primary,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(bottom: 10, left: 4),
                        child: Text(
                          'Spend coins on badges and profile styles. No real money needed.',
                          style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                        ),
                      ),
                      if (_profile != null)
                        Container(
                          margin: const EdgeInsets.only(bottom: 14),
                          padding: const EdgeInsets.all(16),
                          decoration: AppTheme.card(
                            borderColor: AppColors.secondary.withOpacity(0.5),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.verified, color: AppColors.secondary, size: 28),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Text('Premium / Verified',
                                            style: TextStyle(fontWeight: FontWeight.w600)),
                                        if (_profile!.isPremium) ...[
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: AppColors.primary.withOpacity(0.25),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: const Text('OWNED',
                                                style: TextStyle(fontSize: 9, color: AppColors.primary)),
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    const Text(
                                      'A verified badge on your profile, forever.',
                                      style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                                    ),
                                    const SizedBox(height: 6),
                                    CoinBadge(amount: _premiumCost, fontSize: 13),
                                  ],
                                ),
                              ),
                              ElevatedButton(
                                onPressed: (_profile!.isPremium || _purchasingPremium)
                                    ? null
                                    : _purchasePremium,
                                style: ElevatedButton.styleFrom(
                                  disabledBackgroundColor: Colors.white12,
                                  disabledForegroundColor: Colors.white38,
                                ),
                                child: _purchasingPremium
                                    ? const SizedBox(
                                        height: 16,
                                        width: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : Text(_profile!.isPremium ? '✓' : 'Unlock'),
                              ),
                            ],
                          ),
                        ),
                      ..._badges.map((b) => Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(16),
                            decoration: AppTheme.card(
                              borderColor: b.unlocked ? AppColors.primary.withOpacity(0.4) : null,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(b.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                                          if (b.unlocked) ...[
                                            const SizedBox(width: 8),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: AppColors.primary.withOpacity(0.25),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: const Text('OWNED',
                                                  style: TextStyle(fontSize: 9, color: AppColors.primary)),
                                            ),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(b.description,
                                          style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                                      if (b.cost > 0) ...[
                                        const SizedBox(height: 6),
                                        CoinBadge(amount: b.cost, fontSize: 13),
                                      ],
                                    ],
                                  ),
                                ),
                                ElevatedButton(
                                  onPressed: (b.unlocked || b.cost == 0) ? null : () => _purchase(b),
                                  style: ElevatedButton.styleFrom(
                                    disabledBackgroundColor: Colors.white12,
                                    disabledForegroundColor: Colors.white38,
                                  ),
                                  child: Text(b.unlocked ? '✓' : b.cost == 0 ? 'Free' : 'Unlock'),
                                ),
                              ],
                            ),
                          )),
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
