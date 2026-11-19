import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// The label every ad post carries, so an ad is never mistaken for an ordinary post. Paid promotion (a later
/// stage) will say "Promoted" separately; this one only says it is an ad.
class AdLabel extends StatelessWidget {
  const AdLabel({super.key});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4)),
        child: const Text('Ad',
            style: TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.3)),
      );
}

/// The advertiser's own link ("Visit"): a website, a phone number (tel:) or an email (mailto:).
class AdVisitButton extends StatelessWidget {
  final String link;
  const AdVisitButton({super.key, required this.link});

  static Uri? uriFor(String link) {
    final l = link.trim();
    if (l.isEmpty) return null;
    final uri = Uri.tryParse(l.contains(':') ? l : 'https://$l');
    if (uri == null || !const {'http', 'https', 'tel', 'mailto'}.contains(uri.scheme)) return null;
    return uri;
  }

  static String labelFor(String link) {
    final uri = uriFor(link);
    if (uri == null) return 'Visit';
    if (uri.scheme == 'tel') return 'Call';
    if (uri.scheme == 'mailto') return 'Email';
    return 'Visit ${uri.host.replaceFirst(RegExp(r'^www\.'), '')}';
  }

  @override
  Widget build(BuildContext context) {
    final uri = uriFor(link);
    if (uri == null) return const SizedBox.shrink();
    return Material(
      color: Colors.white.withValues(alpha: 0.92),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => launchUrl(uri, mode: LaunchMode.externalApplication),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Flexible(
              child: Text(labelFor(link),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w800, fontSize: 13)),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.open_in_new, size: 15, color: Colors.black),
          ]),
        ),
      ),
    );
  }
}
