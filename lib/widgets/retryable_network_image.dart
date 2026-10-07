import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import '../theme/app_theme.dart';

/// CachedNetworkImage with two things the package doesn't give you on
/// its own:
///
/// 1. A real retry. A failed load (a dropped connection mid-fetch, a
///    mobile browser pausing network while backgrounded) leaves
///    flutter_cache_manager's own on-disk/IndexedDB cache holding that
///    failure for the URL — the package itself only evicts Flutter's
///    in-memory paint-layer image cache on error, not this one, so
///    simply rebuilding the same CachedNetworkImage (a parent's
///    pull-to-refresh, a setState) just replays the same cached
///    failure. This clears flutter_cache_manager's entry for that
///    exact URL and forces a fresh element via a changed key, so a
///    retry genuinely re-fetches from the network instead of nothing
///    happening.
///
/// 2. A guarantee against a blank/black card. Confirmed live on web: a
///    thumbnail can render correctly, then — with no error, no
///    errorWidget ever firing — go solid black a few seconds later
///    (the GPU-side decode/paint failing silently, a known soft spot
///    for CanvasKit, Flutter web's only renderer, under memory
///    pressure). CachedNetworkImage's own placeholder/errorWidget only
///    cover "still loading" and "explicitly errored" — neither covers
///    "loaded fine, then silently stopped painting." Two things close
///    that gap: a solid, always-present base layer behind the image
///    (so a silent failure reveals the app's own surface color, never
///    a void the dark background shows through as pure black), and
///    confirming success only through `imageBuilder`, which the
///    package only ever calls once a frame has actually decoded — the
///    same "initialized != rendered" distinction a video player needs.
///    If that confirmation hasn't landed within [_autoRetryAfter], this
///    retries automatically, the same way the explicit error path
///    already did on tap.
class RetryableNetworkImage extends StatefulWidget {
  final String imageUrl;
  final BoxFit fit;
  final Widget Function(BuildContext, String)? placeholder;
  // Shown on an explicit load error (tap to retry still works
  // underneath whatever's passed here — see the default below for the
  // generic case). Callers with their own branded empty state (a
  // series' poster placeholder, say) pass that instead so a genuine
  // error still reads as "no cover set" rather than a generic broken-
  // image icon that doesn't match the rest of that card's design.
  final Widget Function(BuildContext, String, Object)? errorWidget;
  // Caps the actual decoded pixel size, independent of the source
  // file's own resolution — without this, an oversized source image
  // (a multi-megapixel screenshot-as-thumbnail, say) gets decoded at
  // full size before Flutter ever scales it down for display, which
  // on web's CanvasKit renderer (the only renderer recent Flutter
  // versions ship — the old html-renderer escape hatch no longer
  // exists) is slow enough on a phone browser's tighter memory budget
  // to stall or silently fail to paint. 480 covers even a 3x-density
  // phone screen's worth of a normal grid thumbnail with headroom;
  // callers displaying something larger (a full-bleed hero image)
  // should pass a bigger value.
  final int memCacheWidth;
  const RetryableNetworkImage({
    super.key,
    required this.imageUrl,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorWidget,
    this.memCacheWidth = 480,
  });

  @override
  State<RetryableNetworkImage> createState() => _RetryableNetworkImageState();
}

class _RetryableNetworkImageState extends State<RetryableNetworkImage> {
  static const _autoRetryAfter = Duration(seconds: 12);

  int _attempt = 0;
  bool _retrying = false;
  bool _confirmedRendered = false;
  Timer? _watchdog;

  @override
  void initState() {
    super.initState();
    _armWatchdog();
  }

  @override
  void didUpdateWidget(covariant RetryableNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _confirmedRendered = false;
      _attempt = 0;
      _armWatchdog();
    }
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    super.dispose();
  }

  void _armWatchdog() {
    _watchdog?.cancel();
    _watchdog = Timer(_autoRetryAfter, () {
      // Only fires if imageBuilder never confirmed a real decode in
      // time — a genuinely slow-but-working load gets more time on its
      // next attempt anyway, since the watchdog re-arms per attempt.
      if (!_confirmedRendered && mounted) _retry();
    });
  }

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
    if (!mounted) return;
    setState(() {
      _attempt++;
      _retrying = false;
    });
    _armWatchdog();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      // Always-present base layer — see the class doc for why this,
      // not just a placeholder, is what actually makes a black card
      // impossible regardless of which failure mode causes it.
      color: AppColors.surfaceBorder,
      child: CachedNetworkImage(
        key: ValueKey('${widget.imageUrl}_$_attempt'),
        imageUrl: widget.imageUrl,
        fit: widget.fit,
        memCacheWidth: widget.memCacheWidth,
        placeholder: widget.placeholder,
        imageBuilder: (context, imageProvider) {
          _confirmedRendered = true;
          return Container(
            decoration: BoxDecoration(
              image: DecorationImage(image: imageProvider, fit: widget.fit),
            ),
          );
        },
        errorWidget: (ctx, url, error) => GestureDetector(
          onTap: _retry,
          child: widget.errorWidget?.call(ctx, url, error) ??
              Container(
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
      ),
    );
  }
}
