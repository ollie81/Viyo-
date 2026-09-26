import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Renders `||text||` as a redacted, tap-to-reveal span — the Reddit/
/// Discord spoiler-tag convention. Client-side only: the `comments`
/// table has no spoiler column and can't get one without a schema
/// migration this codebase can't run itself, so the markup itself
/// carries the state instead of a database flag.
class SpoilerText extends StatefulWidget {
  final String text;
  final TextStyle? style;

  const SpoilerText({super.key, required this.text, this.style});

  @override
  State<SpoilerText> createState() => _SpoilerTextState();
}

class _SpoilerTextState extends State<SpoilerText> {
  static final _spoilerPattern = RegExp(r'\|\|(.+?)\|\|', dotAll: true);

  // Keyed by match start offset rather than index — stable even if the
  // surrounding text is rebuilt, and simple since a comment's text
  // itself never changes after render.
  final Set<int> _revealed = {};

  @override
  Widget build(BuildContext context) {
    final baseStyle = widget.style ?? DefaultTextStyle.of(context).style;
    final spans = <InlineSpan>[];
    var cursor = 0;

    for (final match in _spoilerPattern.allMatches(widget.text)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: widget.text.substring(cursor, match.start)));
      }
      final revealed = _revealed.contains(match.start);
      final hidden = match.group(1) ?? '';
      spans.add(
        TextSpan(
          text: revealed ? hidden : '█' * hidden.length.clamp(3, 24),
          style: revealed
              ? null
              : TextStyle(
                  color: Colors.transparent,
                  backgroundColor: AppColors.surfaceBorder,
                ),
          recognizer: TapGestureRecognizer()
            ..onTap = () => setState(() => _revealed.add(match.start)),
        ),
      );
      cursor = match.end;
    }
    if (cursor < widget.text.length) {
      spans.add(TextSpan(text: widget.text.substring(cursor)));
    }

    // No spoiler markup at all — the common case — renders as one
    // plain span, same output as a bare Text widget would have given.
    if (spans.length == 1 && spans.first is TextSpan && (spans.first as TextSpan).recognizer == null) {
      return Text(widget.text, style: baseStyle);
    }

    return Text.rich(TextSpan(style: baseStyle, children: spans));
  }
}
