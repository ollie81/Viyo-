import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// A small animated toast banner, meant to sit inside a Stack via
/// Positioned. Replaces the identical "pop in with no animation, vanish
/// after 2s" toast that was duplicated across Wallet, Store, and Missions.
class ViyoToast extends StatelessWidget {
  final String message;

  const ViyoToast({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 16,
      left: 40,
      right: 40,
      child: TweenAnimationBuilder<double>(
        key: ValueKey(message),
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        builder: (context, t, child) => Opacity(
          opacity: t,
          child: Transform.translate(offset: Offset(0, (1 - t) * -14), child: child),
        ),
        child: Material(
          color: AppColors.secondary,
          borderRadius: BorderRadius.circular(30),
          elevation: 8,
          shadowColor: AppColors.secondary.withOpacity(0.4),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
            ),
          ),
        ),
      ),
    );
  }
}
