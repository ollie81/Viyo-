import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../services/profile_service.dart';
import '../../theme/app_theme.dart';
import '../home/home_shell.dart';
import 'signup_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  bool _resending = false;
  bool _obscurePassword = true;
  String? _error;
  bool _showResend = false;
  bool _continuingAsGuest = false;

  Future<void> _login() async {
    setState(() {
      _loading = true;
      _error = null;
      _showResend = false;
    });
    try {
      await AuthService.signIn(
        email: _email.text.trim(),
        password: _password.text,
      );
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeShell()),
        (_) => false,
      );
    } catch (e) {
      final msg = e.toString().toLowerCase();
      setState(() {
        _error = 'Login failed: $e';
        _showResend = msg.contains('confirm');
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resendConfirmation() async {
    setState(() => _resending = true);
    try {
      await AuthService.resendConfirmation(_email.text.trim());
      if (!mounted) return;
      setState(() => _error = 'Confirmation email resent. Check your inbox.');
    } catch (e) {
      setState(() => _error = 'Could not resend: $e');
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  /// Reaching this screen at all means the app's automatic anonymous
  /// sign-in (see main.dart's SplashScreen) already failed once — could be
  /// a real problem (anonymous sign-ins disabled in the Supabase project)
  /// or just a transient network blip. This gives a visible way to retry
  /// it instead of silently stranding someone on a login wall with no
  /// indication guest browsing was ever an option.
  Future<void> _continueAsGuest() async {
    setState(() {
      _continuingAsGuest = true;
      _error = null;
    });
    try {
      final response = await AuthService.signInAnonymously();
      final userId = response.user?.id;
      if (userId == null) {
        throw Exception('No session returned');
      }

      try {
        await ProfileService.getProfile(userId);
      } catch (_) {
        await AuthService.createGuestProfile(userId);
      }

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeShell()),
        (_) => false,
      );
    } catch (e) {
      setState(() => _error = 'Could not continue as guest: $e');
    } finally {
      if (mounted) setState(() => _continuingAsGuest = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Viyo',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 44,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Welcome back, Creator',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 28),
              OutlinedButton(
                onPressed: _continuingAsGuest ? null : _continueAsGuest,
                child: _continuingAsGuest
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Continue as Guest'),
              ),
              const SizedBox(height: 20),
              const Row(
                children: [
                  Expanded(child: Divider(color: AppColors.surfaceBorder)),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10),
                    child: Text('or', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                  ),
                  Expanded(child: Divider(color: AppColors.surfaceBorder)),
                ],
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(hintText: 'Email'),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _password,
                obscureText: _obscurePassword,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Password',
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword ? Icons.visibility_off : Icons.visibility,
                      color: AppColors.textSecondary,
                    ),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
              ],
              if (_showResend) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _resending ? null : _resendConfirmation,
                  child: _resending
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Resend confirmation email'),
                ),
              ],
              const SizedBox(height: 22),
              ElevatedButton(
                onPressed: _loading ? null : _login,
                child: _loading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Log In'),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SignupScreen()),
                ),
                child: const Text(
                  "Don't have an account? Sign up",
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

