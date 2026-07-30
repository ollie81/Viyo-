import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/supabase_service.dart';
import 'services/profile_service.dart';
import 'theme/app_theme.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/onboarding_screen.dart';
import 'screens/home/home_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );
  await SupabaseService.init();
  runApp(const ViyoApp());
}

class ViyoApp extends StatelessWidget {
  const ViyoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Viyo',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _route();
  }

  Future<void> _route() async {
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;

    final userId = SupabaseService.currentUserId;
    if (userId == null) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
      return;
    }

    // Logged in — but do they have a profile yet? (edge case: user signed
    // up but closed the app during onboarding)
    try {
      await ProfileService.getProfile(userId);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeShell()),
      );
    } catch (_) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => OnboardingScreen(userId: userId)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Viyo',
              style: TextStyle(
                fontSize: 42,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
            SizedBox(height: 12),
            Text(
              'Creator Boost',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 16),
            ),
            SizedBox(height: 40),
            CircularProgressIndicator(color: AppColors.secondary),
          ],
        ),
      ),
    );
  }
}
