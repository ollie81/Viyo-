import 'package:flutter/material.dart';

/// Central design tokens for Viyo. Import this everywhere instead of
/// hardcoding hex colors in widgets, so the palette stays consistent
/// as the app grows.
class AppColors {
  static const background = Color(0xFF0B0B1A);
  static const surface = Color(0xFF13132B);
  static const surfaceBorder = Color(0xFF1E1E3A);

  static const primary = Color(0xFF00E5FF); // bright cyan
  static const secondary = Color(0xFFA855F7); // purple
  static const coin = Color(0xFFFBBF24); // gold

  static const success = Color(0xFF22C55E);
  static const danger = Colors.redAccent;

  static const textPrimary = Colors.white;
  static const textSecondary = Colors.white54;
  static const textMuted = Colors.white38;
}

/// Reusable gradients for surfaces that should feel like a "hero" — the
/// level card, the AI Coach nudge — instead of a flat AppColors.surface
/// fill. Kept separate from AppColors so plain cards stay untouched.
class AppGradients {
  static const primary = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF17173A), Color(0xFF1B1440)],
  );

  static const coin = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFDE68A), AppColors.coin],
  );
}

class AppTheme {
  static ThemeData get dark {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.background,
      primaryColor: AppColors.primary,
      useMaterial3: true,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.primary,
        secondary: AppColors.secondary,
        surface: AppColors.surface,
      ),
      fontFamily: 'Roboto',
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.bold,
          color: AppColors.textPrimary,
        ),
        titleLarge: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
        bodyMedium: TextStyle(fontSize: 14, color: AppColors.textPrimary),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.background,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white70,
          side: const BorderSide(color: AppColors.surfaceBorder),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        hintStyle: const TextStyle(color: AppColors.textMuted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.primary),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.surface,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textSecondary,
      ),
    );
  }

  static BoxDecoration card({Color? borderColor}) => BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor ?? AppColors.surfaceBorder),
      );

  /// A card with a soft, colored glow — for the one or two surfaces per
  /// screen that should draw the eye (a hero stat, the AI Coach nudge),
  /// not for every card everywhere.
  static BoxDecoration glowCard({
    required Color glowColor,
    Gradient? gradient,
    double glowOpacity = 0.28,
  }) =>
      BoxDecoration(
        color: gradient == null ? AppColors.surface : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: glowColor.withOpacity(0.45)),
        boxShadow: [
          BoxShadow(
            color: glowColor.withOpacity(glowOpacity),
            blurRadius: 24,
            spreadRadius: -4,
            offset: const Offset(0, 10),
          ),
        ],
      );
}
