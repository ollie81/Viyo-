import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../main.dart' show SplashScreen;
import '../services/auth_service.dart';
import '../services/supabase_service.dart';

/// "Continue with Google". On the web the page goes to Google and comes
/// back signed in. In the Android app Google opens in the browser and the
/// app picks the session up when it returns; this button then restarts the
/// normal start-up routing (home, or onboarding for a new account).
class GoogleSignInButton extends StatefulWidget {
  final VoidCallback? onSignedIn;
  /// Space around the button, so hiding it (Google not enabled yet)
  /// doesn't leave a gap.
  final EdgeInsets padding;
  const GoogleSignInButton({super.key, this.onSignedIn, this.padding = EdgeInsets.zero});

  @override
  State<GoogleSignInButton> createState() => _GoogleSignInButtonState();
}

class _GoogleSignInButtonState extends State<GoogleSignInButton> {
  bool _busy = false;
  StreamSubscription<AuthState>? _sub;

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _go() async {
    setState(() => _busy = true);
    _sub ??= SupabaseService.client.auth.onAuthStateChange.listen((state) {
      final user = state.session?.user;
      final done = (state.event == AuthChangeEvent.signedIn || state.event == AuthChangeEvent.userUpdated) &&
          user != null && !user.isAnonymous;
      if (!done || !mounted) return;
      _sub?.cancel();
      _sub = null;
      if (widget.onSignedIn != null) {
        widget.onSignedIn!();
      } else {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const SplashScreen()),
          (_) => false,
        );
      }
    });
    try {
      await AuthService.continueWithGoogle();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't open Google sign-in. Try again.")),
        );
      }
    } finally {
      // On the web the page navigates away; in the app we wait for the
      // sign-in event above, so only re-enable the button.
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: AuthService.googleEnabled(),
      builder: (context, snap) => snap.data == true
          ? Padding(padding: widget.padding, child: _button())
          : const SizedBox.shrink(),
    );
  }

  Widget _button() {
    return OutlinedButton(
      onPressed: _busy ? null : _go,
      style: OutlinedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1F1F1F),
        side: const BorderSide(color: Color(0xFFDADCE0)),
        minimumSize: const Size.fromHeight(48),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            child: const Text('G',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF4285F4))),
          ),
          const SizedBox(width: 10),
          Text(_busy ? 'Opening Google...' : 'Continue with Google',
              style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF1F1F1F))),
        ],
      ),
    );
  }
}
