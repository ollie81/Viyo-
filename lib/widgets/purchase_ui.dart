import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Shared building blocks for VIYO's real-money screens (Buy Coins, Premium): one card shape, one radius, one
/// selection language. Gold marks coins, cyan marks Premium.
class PurchaseUi {
  static const radius = 16.0;
  static const gap = 12.0;
  static const maxWidth = 640.0;
}

/// Centres the content at a comfortable reading width on desktop; full width with 16px gutters on phones.
class PurchaseBody extends StatelessWidget {
  final List<Widget> children;
  final Widget? bottom;
  const PurchaseBody({super.key, required this.children, this.bottom});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: PurchaseUi.maxWidth),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
                ),
              ),
            ],
          ),
        ),
        if (bottom != null)
          DecoratedBox(
            decoration: const BoxDecoration(
              color: AppColors.background,
              border: Border(top: BorderSide(color: AppColors.surfaceBorder)),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: PurchaseUi.maxWidth),
                    child: bottom,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class PurchaseSectionLabel extends StatelessWidget {
  final String text;
  const PurchaseSectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 10),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
            color: AppColors.textSecondary, fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 1.1),
      ),
    );
  }
}

/// A selectable card: accent border and a filled radio when selected, dimmed when it can't be chosen.
class SelectableCard extends StatelessWidget {
  final bool selected;
  final bool enabled;
  final Color accent;
  final VoidCallback? onTap;
  final Widget child;
  final String semanticsLabel;

  const SelectableCard({
    super.key,
    required this.selected,
    required this.accent,
    required this.child,
    required this.semanticsLabel,
    this.enabled = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final border = selected && enabled ? accent : AppColors.surfaceBorder;
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: semanticsLabel,
      child: Opacity(
        opacity: enabled ? 1 : 0.55,
        child: Material(
          color: selected && enabled ? Color.alphaBlend(accent.withAlpha(18), AppColors.surface) : AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(PurchaseUi.radius),
            side: BorderSide(color: border, width: selected && enabled ? 1.6 : 1),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled ? onTap : null,
            child: Padding(padding: const EdgeInsets.all(16), child: child),
          ),
        ),
      ),
    );
  }
}

class SelectionDot extends StatelessWidget {
  final bool selected;
  final Color accent;
  const SelectionDot({super.key, required this.selected, required this.accent});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: selected ? accent : AppColors.textMuted, width: 2),
      ),
      alignment: Alignment.center,
      child: selected
          ? Container(width: 10, height: 10, decoration: BoxDecoration(shape: BoxShape.circle, color: accent))
          : null,
    );
  }
}

/// A small pill: "Save 30%", "Not available", "Soon".
class PurchaseChip extends StatelessWidget {
  final String text;
  final Color color;
  const PurchaseChip(this.text, {super.key, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withAlpha(90)),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}

enum NoticeTone { info, waiting, error, success }

/// An inline notice (no dialogs or sheets): why something can't be bought, a pending payment, an error.
class PurchaseNotice extends StatelessWidget {
  final NoticeTone tone;
  final String title;
  final String? message;
  final Widget? action;

  const PurchaseNotice({super.key, required this.tone, required this.title, this.message, this.action});

  @override
  Widget build(BuildContext context) {
    final (Color color, IconData icon) = switch (tone) {
      NoticeTone.info => (AppColors.textSecondary, Icons.info_outline_rounded),
      NoticeTone.waiting => (AppColors.primary, Icons.hourglass_top_rounded),
      NoticeTone.error => (AppColors.danger, Icons.error_outline_rounded),
      NoticeTone.success => (AppColors.success, Icons.check_circle_outline_rounded),
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(PurchaseUi.radius),
        border: Border.all(color: tone == NoticeTone.info ? AppColors.surfaceBorder : color.withAlpha(110)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: tone == NoticeTone.waiting
                ? SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: color))
                : Icon(icon, size: 19, color: tone == NoticeTone.info ? AppColors.textPrimary : color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, height: 1.3)),
                if (message != null) ...[
                  const SizedBox(height: 4),
                  Text(message!, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.45)),
                ],
                if (action != null) ...[const SizedBox(height: 10), action!],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The one primary action at the bottom of a purchase screen. Shows a spinner while busy.
class PurchaseButton extends StatelessWidget {
  final String label;
  final Color accent;
  final bool busy;
  final VoidCallback? onPressed;

  const PurchaseButton({super.key, required this.label, required this.accent, this.busy = false, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      width: double.infinity,
      child: ElevatedButton(
        onPressed: busy ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: AppColors.background,
          disabledBackgroundColor: AppColors.surfaceBorder,
          disabledForegroundColor: AppColors.textMuted,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, letterSpacing: 0.2),
          elevation: 0,
        ),
        child: busy
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4))
            : Text(label),
      ),
    );
  }
}

/// A short line of reassurance under the primary action.
class PurchaseFinePrint extends StatelessWidget {
  final String text;
  const PurchaseFinePrint(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(Icons.lock_outline_rounded, size: 13, color: AppColors.textMuted),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(text,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5, height: 1.4)),
          ),
        ],
      ),
    );
  }
}

/// Loading placeholder shaped like the content, so the screen doesn't jump.
class PurchaseSkeleton extends StatelessWidget {
  final int cards;
  const PurchaseSkeleton({super.key, this.cards = 4});

  @override
  Widget build(BuildContext context) {
    return PurchaseBody(children: [
      for (var i = 0; i < cards; i++)
        Container(
          height: 78,
          margin: const EdgeInsets.only(bottom: PurchaseUi.gap),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(PurchaseUi.radius),
            border: Border.all(color: AppColors.surfaceBorder),
          ),
        ),
    ]);
  }
}
