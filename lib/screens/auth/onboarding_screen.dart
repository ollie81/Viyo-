import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../home/home_shell.dart';

class OnboardingScreen extends StatefulWidget {
  final String userId;
  const OnboardingScreen({super.key, required this.userId});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _displayName = TextEditingController();
  final _username = TextEditingController();
  final _referralCode = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _finish() async {
    final username = _username.text.trim().toLowerCase();
    final displayName = _displayName.text.trim();

    if (username.isEmpty || displayName.isEmpty) {
      setState(() => _error = 'Please fill in your name and username');
      return;
    }
    if (!RegExp(r'^[a-z0-9_]{3,20}$').hasMatch(username)) {
      setState(() => _error =
          'Username must be 3-20 characters: letters, numbers, underscore only');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final available = await AuthService.isUsernameAvailable(username);
      if (!available) {
        setState(() {
          _error = 'That username is taken';
          _loading = false;
        });
        return;
      }

      await AuthService.createProfile(
        userId: widget.userId,
        username: username,
        displayName: displayName,
        referredByCode: _referralCode.text.trim().isEmpty
            ? null
            : _referralCode.text.trim(),
      );

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeShell()),
        (_) => false,
      );
    } catch (e) {
      setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),
              const Text(
                'Welcome, Creator',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              const Text(
                'Tell us a bit about you to get started.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _displayName,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(hintText: 'Your name'),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _username,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(hintText: 'Username (e.g. jane_creates)'),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _referralCode,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(hintText: 'Referral code (optional)'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
              ],
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _loading ? null : _finish,
                child: _loading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Start Boosting →'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
