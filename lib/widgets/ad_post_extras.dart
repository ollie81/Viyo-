import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/promotion_service.dart';

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

/// Paid placement (a paid promotion or a coin boost) is always labelled as such, next to the Ad label.
class PromotedLabel extends StatelessWidget {
  const PromotedLabel({super.key});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(color: const Color(0xFFA855F7), borderRadius: BorderRadius.circular(4)),
        child: const Text('Promoted',
            style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.3)),
      );
}

/// A post a creator made for a brand campaign (paid by the brand through VIYO).
class SponsoredLabel extends StatelessWidget {
  final String brand;
  const SponsoredLabel({super.key, required this.brand});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(color: const Color(0xFF0EA5E9), borderRadius: BorderRadius.circular(4)),
        child: Text('Sponsored · $brand',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.3)),
      );
}

/// The advertiser's own link ("Visit"): a website, a phone number (tel:) or an email (mailto:).
class AdVisitButton extends StatelessWidget {
  final String link;
  final String? promotionId; // set on a promoted post: a tap is counted for the advertiser's report
  const AdVisitButton({super.key, required this.link, this.promotionId});

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
        onTap: () {
          if (promotionId != null) PromotionService.recordClick(promotionId!);
          launchUrl(uri, mode: LaunchMode.externalApplication);
        },
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

/// Calls [onSeen] once, the first time at least half of [child] is on screen (checked on layout and on every
/// scroll of the nearest scrollable). Used so a promoted ad only counts as an impression when it was really seen.
class SeenOnScreen extends StatefulWidget {
  final Widget child;
  final VoidCallback onSeen;
  const SeenOnScreen({super.key, required this.child, required this.onSeen});

  @override
  State<SeenOnScreen> createState() => _SeenOnScreenState();
}

class _SeenOnScreenState extends State<SeenOnScreen> {
  bool _done = false;
  ScrollPosition? _position;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _position?.removeListener(_check);
    _position = Scrollable.maybeOf(context)?.position;
    _position?.addListener(_check);
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void dispose() {
    _position?.removeListener(_check);
    super.dispose();
  }

  void _check() {
    if (_done || !mounted) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) return;
    final top = box.localToGlobal(Offset.zero).dy;
    final h = box.size.height;
    final screen = MediaQuery.sizeOf(context).height;
    final visible = (top + h).clamp(0.0, screen) - top.clamp(0.0, screen);
    if (h > 0 && visible >= h / 2) {
      _done = true;
      _position?.removeListener(_check);
      widget.onSeen();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
