import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../../models/user_profile.dart';
import '../../services/profile_service.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';

class InviteScreen extends StatefulWidget {
  const InviteScreen({super.key});

  @override
  State<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends State<InviteScreen> {
  UserProfile? _profile;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final userId = SupabaseService.currentUserId;
    if (userId == null) return;
    final profile = await ProfileService.getProfile(userId);
    if (!mounted) return;
    setState(() => _profile = profile);
  }

  Future<void> _share() async {
    if (_profile == null) return;
    await Share.share(
      "Join me on Viyo — the creator motivation app! Use my code ${_profile!.referralCode} and we both earn coins. 🚀",
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: AppColors.background, title: const Text('Invite Friends')),
      body: _profile == null
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const Icon(Icons.card_giftcard, size: 56, color: AppColors.secondary),
                  const SizedBox(height: 16),
                  const Text(
                    'Invite a friend, you both earn coins',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'You get +20 coins, your friend gets +10 coins when they join with your code.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 28),
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 24),
                    decoration: AppTheme.card(),
                    child: Column(
                      children: [
                        const Text('Your referral code', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                        const SizedBox(height: 8),
                        Text(
                          _profile!.referralCode,
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                            letterSpacing: 2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(onPressed: _share, child: const Text('Share Invite ↗')),
                  ),
                ],
              ),
            ),
    );
  }
}
