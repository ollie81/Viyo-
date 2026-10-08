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
///
/// The retry watchdog is progress-aware, not a flat timeout — an
/// earlier version just retried if nothing had confirmed within a
/// fixed window, which on a genuinely slow connection (not a stalled
/// one) was actively self-defeating: a real download that legitimately
/// takes 15+ seconds on a slow connection kept getting cancelled and
/// restarted from zero bytes just before it would have finished,
/// forever, which reads to the viewer as a permanently stuck black
/// card on exactly the connections most likely to produce one.
/// flutter_cache_manager's progressIndicatorBuilder reports cumulative
/// bytes downloaded on every real chunk received, so this instead
/// polls whether that count has moved since the last check — a
/// download that's still receiving bytes, however slowly, is left
/// alone indefinitely; only a connection that's gone genuinely silent
/// (zero new bytes across several checks — a dropped connection, a
/// backgrounded tab's network paused) triggers the destructive retry.
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
  // How often the stall check runs, and how many consecutive checks
  // with zero new bytes count as "actually stuck" rather than "just
  // slow". 4 checks x 5s = 20s of genuine silence before retrying —
  // generous on purpose, since the cost of waiting a bit longer on a
  // real stall is low, while retrying a slow-but-live download is what
  // this whole rewrite exists to stop doing.
  static const _stallCheckInterval = Duration(seconds: 5);
  static const _maxSilentChecks = 4;

  int _attempt = 0;
  bool _retrying = false;
  bool _confirmedRendered = false;
  Timer? _stallTimer;
  int _downloadedBytes = 0;
  int _lastCheckedBytes = -1;
  int _silentChecks = 0;

  @override
  void initState() {
    super.initState();
    _armStallTimer();
  }

  @override
  void didUpdateWidget(covariant RetryableNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _confirmedRendered = false;
      _attempt = 0;
      _armStallTimer();
    }
  }

  @override
  void dispose() {
    _stallTimer?.cancel();
    super.dispose();
  }

  void _armStallTimer() {
    _stallTimer?.cancel();
    _downloadedBytes = 0;
    _lastCheckedBytes = -1;
    _silentChecks = 0;
    _stallTimer = Timer.periodic(_stallCheckInterval, (_) => _checkForStall());
  }

  void _checkForStall() {
    if (!mounted || _confirmedRendered) {
      _stallTimer?.cancel();
      return;
    }
    if (_downloadedBytes > _lastCheckedBytes) {
      // Bytes have actually moved since the last check — a live,
      // progressing download, however slow. Reset the silence count
      // instead of retrying; there's no fixed deadline for this at
      // all as long as it keeps making real progress.
      _lastCheckedBytes = _downloadedBytes;
      _silentChecks = 0;
      return;
    }
    _silentChecks++;
    if (_silentChecks >= _maxSilentChecks) {
      _stallTimer?.cancel();
      _retry();
    }
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
    _armStallTimer();
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
        progressIndicatorBuilder: (context, url, progress) {
          _downloadedBytes = progress.downloaded;
          return widget.placeholder?.call(context, url) ?? const SizedBox.shrink();
        },
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
