import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import '../theme/app_theme.dart';

/// CachedNetworkImage with a retry that actually works. A failed load
/// (a dropped connection mid-fetch, a mobile browser pausing network
/// while backgrounded) leaves flutter_cache_manager's own on-disk/
/// IndexedDB cache holding that failure for the URL — the package
/// itself only evicts Flutter's in-memory paint-layer image cache on
/// error, not this one, so simply rebuilding the same CachedNetworkImage
/// (a parent's pull-to-refresh, a setState) just replays the same
/// cached failure. This clears flutter_cache_manager's entry for that
/// exact URL and forces a fresh element via a changed key, so a retry
/// genuinely re-fetches from the network instead of nothing happening.
class RetryableNetworkImage extends StatefulWidget {
  final String imageUrl;
  final BoxFit fit;
  final Widget Function(BuildContext, String)? placeholder;
  const RetryableNetworkImage({
    super.key,
    required this.imageUrl,
    this.fit = BoxFit.cover,
    this.placeholder,
  });

  @override
  State<RetryableNetworkImage> createState() => _RetryableNetworkImageState();
}

class _RetryableNetworkImageState extends State<RetryableNetworkImage> {
  int _attempt = 0;
  bool _retrying = false;

  Future<void> _retry() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    try {
      await DefaultCacheManager().removeFile(widget.imageUrl);
    } catch (_) {
      // Best-effort — even if the cache-manager removal fails, the
      // changed key below still forces a new CachedNetworkImage
      // element, which is itself a real (if less certain) retry.
    }
    if (mounted) setState(() { _attempt++; _retrying = false; });
  }

  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      key: ValueKey('${widget.imageUrl}_$_attempt'),
      imageUrl: widget.imageUrl,
      fit: widget.fit,
      placeholder: widget.placeholder,
      errorWidget: (_, __, ___) => GestureDetector(
        onTap: _retry,
        child: Container(
          color: AppColors.surfaceBorder,
          alignment: Alignment.center,
          child: _retrying
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textMuted),
                )
              : const Icon(Icons.refresh, color: AppColors.textMuted, size: 20),
        ),
      ),
    );
  }
}
