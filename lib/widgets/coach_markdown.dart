import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Renders the small slice of markdown the Coach actually writes.
///
/// The model has always emitted `**bold**`, `- ` bullets and numbered
/// steps; the app rendered them as literal asterisks and hyphens, so
/// coaching that was structured on the way out arrived as a wall of
/// punctuation. This handles exactly what shows up — bold, italic,
/// inline code, bullets, numbered lists and `## ` headings — rather
/// than pulling in a full markdown package for six constructs.
///
/// Anything it doesn't recognise falls through as plain text, which is
/// the right failure: a creator should never lose a sentence because
/// the model reached for syntax this doesn't know.
class CoachMarkdown extends StatelessWidget {
  final String text;
  final TextStyle baseStyle;

  const CoachMarkdown({
    super.key,
    required this.text,
    this.baseStyle = const TextStyle(fontSize: 14, height: 1.45),
  });

  @override
  Widget build(BuildContext context) {
    final blocks = <Widget>[];

    for (final rawLine in text.split('\n')) {
      final line = rawLine.trimRight();

      if (line.trim().isEmpty) {
        // Collapse runs of blank lines — the model is inconsistent about
        // how many it leaves, and three blank lines on a phone screen is
        // just a hole in the conversation.
        if (blocks.isNotEmpty) {
          blocks.add(const SizedBox(height: 8));
        }
        continue;
      }

      final heading = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(line.trimLeft());
      if (heading != null) {
        blocks.add(Padding(
          padding: EdgeInsets.only(top: blocks.isEmpty ? 0 : 6, bottom: 2),
          child: _rich(
            heading.group(2)!,
            baseStyle.copyWith(
              fontWeight: FontWeight.w800,
              fontSize: baseStyle.fontSize! + 1,
            ),
          ),
        ));
        continue;
      }

      final bullet = RegExp(r'^\s*[-*•]\s+(.*)$').firstMatch(line);
      if (bullet != null) {
        blocks.add(_listRow('•', bullet.group(1)!));
        continue;
      }

      final numbered = RegExp(r'^\s*(\d{1,2})[.)]\s+(.*)$').firstMatch(line);
      if (numbered != null) {
        blocks.add(_listRow('${numbered.group(1)}.', numbered.group(2)!));
        continue;
      }

      blocks.add(_rich(line, baseStyle));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: blocks,
    );
  }

  Widget _listRow(String marker, String content) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 20,
            child: Text(
              marker,
              style: baseStyle.copyWith(
                color: AppColors.secondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(child: _rich(content, baseStyle)),
        ],
      ),
    );
  }

  /// Inline spans: **bold**, *italic*/_italic_, `code`.
  Widget _rich(String source, TextStyle style) {
    return RichText(text: TextSpan(style: style, children: _spans(source, style)));
  }

  static final RegExp _inline = RegExp(
    r'\*\*(.+?)\*\*'      // bold
    r'|__(.+?)__'         // bold
    r'|\*(.+?)\*'         // italic
    r'|_(.+?)_'           // italic
    r'|`(.+?)`',          // inline code
    dotAll: true,
  );

  List<TextSpan> _spans(String source, TextStyle style) {
    final spans = <TextSpan>[];
    var index = 0;

    for (final match in _inline.allMatches(source)) {
      if (match.start > index) {
        spans.add(TextSpan(text: source.substring(index, match.start)));
      }

      if (match.group(1) != null || match.group(2) != null) {
        spans.add(TextSpan(
          text: match.group(1) ?? match.group(2),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ));
      } else if (match.group(3) != null || match.group(4) != null) {
        spans.add(TextSpan(
          text: match.group(3) ?? match.group(4),
          style: const TextStyle(fontStyle: FontStyle.italic),
        ));
      } else {
        spans.add(TextSpan(
          text: match.group(5),
          style: TextStyle(
            fontFamily: 'monospace',
            backgroundColor: AppColors.secondary.withOpacity(0.14),
          ),
        ));
      }

      index = match.end;
    }

    if (index < source.length) {
      spans.add(TextSpan(text: source.substring(index)));
    }

    return spans;
  }
}
