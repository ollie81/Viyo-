import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'constants/supabase_constants.dart';
import 'services/analytics_service.dart';
import 'services/auth_service.dart';
import 'services/google_play_purchase_service.dart';
import 'services/push_notification_service.dart';
import 'services/rewarded_ad_service.dart';
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

  // Must subscribe before anything else happens — see its own doc
  // comment for why a purchase completed while nobody was listening
  // (e.g. the app was killed mid-purchase) only gets redelivered on
  // the next app launch.
  GooglePlayPurchaseService.init();

  // google_mobile_ads has no web implementation at all — calling any of
  // its APIs on web (including RewardedAdService.preload(), which reads
  // dart:io's Platform.isIOS) throws before the first frame ever
  // renders, which is exactly what blanked the Vercel web build. Skip
  // both entirely on web; RewardedAdService's own calls stay guarded
  // too; see its doc comment.
  if (!kIsWeb) {
    // Fire-and-forget: MobileAds.instance.initialize() resolves once ad
    // SDKs are ready, but nothing here needs to block app start on that.
    // preload() queues the first rewarded ad request right behind it.
    MobileAds.instance.initialize();
    RewardedAdService.preload();
  }

  // SentryFlutter.init no-ops when SentryConstants.dsn is blank (see its
  // definition) — safe to always call, crash reporting just stays off
  // until a real DSN is filled in.
  await SentryFlutter.init(
    (options) {
      options.dsn = SentryConstants.dsn;
      options.tracesSampleRate = 0.2;
    },
    appRunner: () => runApp(const ViyoApp()),
  );
}

class ViyoApp extends StatelessWidget {
  const ViyoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Viyo',
      debugShowCheckedModeBanner: false,
      navigatorKey: PushNotificationService.navigatorKey,
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

    var userId = SupabaseService.currentUserId;

    // No session at all yet — start one anonymously instead of showing a
    // login wall. This is a real, verifiable Supabase session (just
    // flagged is_anonymous), so everything downstream treats it exactly
    // like a signed-in user except for the features gated behind
    // GuestGate. Falls back to the login screen only if anonymous
    // sign-in itself isn't available (e.g. disabled in the Supabase
    // project's Auth settings).
    if (userId == null) {
      try {
        final response = await AuthService.signInAnonymously();
        userId = response.user?.id;
      } catch (_) {
        userId = null;
      }
    }

    if (userId == null) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
      return;
    }

    // Have a session — but is there a profile row yet?
    try {
      await ProfileService.getProfile(userId);
      unawaited(PushNotificationService.init(userId));
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeShell()),
      );
      return;
    } catch (_) {
      // No profile. A guest gets one auto-created silently — asking a
      // guest to fill in a username before they've even seen the app
      // defeats the point of a no-friction entry. A real signed-up user
      // with no profile yet (e.g. closed the app mid-onboarding) still
      // goes through the real onboarding form.
      if (SupabaseService.isGuest) {
        try {
          await AuthService.createGuestProfile(userId);
          AnalyticsService.track('signup', properties: {'is_guest': true});
          unawaited(PushNotificationService.init(userId));
          if (!mounted) return;
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const HomeShell()),
          );
          return;
        } catch (_) {
          // Fall through to onboarding as a last resort (e.g. a
          // username collision) rather than stranding the guest here.
        }
      }
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => OnboardingScreen(userId: userId!)),
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
