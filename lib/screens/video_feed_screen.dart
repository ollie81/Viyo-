import 'dart:async';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../models/insufficient_coins_exception.dart';
import '../models/post.dart';
import '../models/series.dart';
import '../services/bunny_stream_service.dart';
import '../services/interstitial_ad_service.dart';
import '../services/post_service.dart';
import '../services/rewarded_ad_service.dart';
import '../services/series_service.dart';
import '../services/supabase_service.dart';
import '../services/video_metadata_service.dart';
import '../services/watch_progress_service.dart';
import '../theme/app_theme.dart';
import '../utils/episode_lock.dart';
import '../utils/friendly_error.dart';
import '../widgets/comments_sheet.dart';
import '../widgets/guest_gate.dart';
import '../widgets/insufficient_coins_sheet.dart';
import '../widgets/retryable_network_image.dart';
import '../widgets/up_next_overlay.dart';
import 'profile/profile_screen.dart';
import 'wallet/subscribe_screen.dart';
import '../services/share_links.dart';

/// Viyo's video feed — full-screen, immersive playback (system UI
/// hidden, video filling the whole screen) matching every other
/// short-form/drama app: a back button is the only way out, the same
/// way TikTok/Reels/drama apps work. [seriesId], when set, scopes
/// playback to just that series' episodes in order instead of the
/// global video feed — so opening Episode 1 of a drama naturally swipes
/// (and auto-advances, see _VideoPage.autoAdvance) into Episode 2, 3...
/// without ever needing to back out and pick the next one manually.
class VideoFeedScreen extends StatefulWidget {
  final String? initialPostId;
  final String? seriesId;

  const VideoFeedScreen({super.key, this.initialPostId, this.seriesId});

  @override
  State<VideoFeedScreen> createState() => _VideoFeedScreenState();
}

class _VideoFeedScreenState extends State<VideoFeedScreen> {
  final _pageController = PageController();
  List<Post> _posts = [];
  bool _loading = true;
  int _currentIndex = 0;

  // An interstitial shows every _interstitialEverySwipes swipes for a
  // non-subscriber — fetched once when the feed loads (a stale value
  // for the rest of this screen's life is fine; this gates an ad, not
  // paid content, so it doesn't need episode_unlocks' same-second
  // accuracy). _isSubscriber starts true so a slow/failed fetch fails
  // closed (no ad shown) rather than open (an ad shown to a Premium
  // subscriber who should never see one).
  int _swipesSinceInterstitial = 0;
  static const _interstitialEverySwipes = 6;
  bool _isSubscriber = true;

  // One view recorded per post per time this screen is alive — a post
  // scrolled past and back into view again doesn't recount, but a
  // fresh screen (relaunching the app, reopening the feed) does. Lives
  // here rather than on _VideoPage's own state since that widget is
  // torn down and rebuilt as the PageView recycles pages.
  final Set<String> _viewedPostIds = {};

  @override
  void initState() {
    super.initState();
    // Full-bleed playback: hide the status/nav bars while this screen is
    // up, restore them on the way out — the same immersive treatment
    // every other short-form video screen uses.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    InterstitialAdService.preload();
    _loadSubscriptionStatus();
    _load();
  }

  /// Direct Supabase read, same "read your own state, don't round-trip
  /// through the backend for it" pattern as SeriesService's own
  /// is_subscribed check — this just needs a plain bool, not the full
  /// plan/renewal details SubscriptionService.getStatus() returns.
  Future<void> _loadSubscriptionStatus() async {
    final userId = SupabaseService.currentUserId;
    if (userId == null) {
      if (mounted) setState(() => _isSubscriber = false);
      return;
    }
    try {
      final row = await SupabaseService.client
          .from('profiles')
          .select('is_subscribed')
          .eq('id', userId)
          .maybeSingle();
      if (mounted) setState(() => _isSubscriber = row != null && row['is_subscribed'] == true);
    } catch (_) {
      // Leave _isSubscriber at its fail-closed default (true — see
      // the field's own comment) rather than risk showing an ad to an
      // actual subscriber over a transient network error.
    }
  }

  void _onPageChanged(int i) {
    setState(() => _currentIndex = i);
    if (_isSubscriber) return;
    _swipesSinceInterstitial++;
    if (_swipesSinceInterstitial >= _interstitialEverySwipes) {
      // Reset only once an ad actually showed: if none was loaded yet, try again on the
      // next swipe instead of silently waiting another full round.
      InterstitialAdService.showIfReady().then((shown) {
        if (shown) _swipesSinceInterstitial = 0;
      });
    }
  }

  Future<List<Post>> _fetchPosts() {
    final seriesId = widget.seriesId;
    return seriesId != null
        ? SeriesService.getSeriesEpisodes(seriesId)
        : PostService.getVideoFeed();
  }

  Future<void> _load() async {
    try {
      final posts = await _fetchPosts();
      if (!mounted) return;

      var index = 0;
      if (widget.initialPostId != null) {
        final found = posts.indexWhere((p) => p.id == widget.initialPostId);
        if (found >= 0) index = found;
      }

      setState(() {
        _posts = posts;
        _currentIndex = index;
        _loading = false;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_pageController.hasClients && index > 0) {
          _pageController.jumpToPage(index);
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load videos: ${friendlyErrorMessage(e)}')),
        );
      }
    }
  }

  Future<void> _like(Post post) async {
    final userId = SupabaseService.currentUserId;
    if (userId == null) return;
    if (!await GuestGate.allow(context, action: 'like posts')) return;

    try {
      if (post.likedByMe) {
        await PostService.unlikePost(userId, post.id);
      } else {
        await PostService.likePost(userId, post.id);
      }

      // Refresh the feed so the server's count and liked state remain the
      // source of truth.
      final posts = await _fetchPosts();
      if (!mounted) return;
      setState(() => _posts = posts);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update like: ${friendlyErrorMessage(e)}')),
      );
    }
  }

  void _recordView(Post post) {
    if (!_viewedPostIds.add(post.id)) return; // already counted this session
    PostService.recordView(post.id);
    // The request itself is fire-and-forget (see PostService.recordView),
    // but the count on screen shouldn't just sit there unchanged — bump
    // it locally the moment the view is actually being recorded, same
    // as the like button's own optimistic update.
    setState(() {
      _posts = _posts
          .map((p) => p.id == post.id ? p.copyWith(viewCount: p.viewCount + 1) : p)
          .toList();
    });
  }

  /// Lets the owner of a drama episode (or any other video post) delete
  /// it straight from the feed they're actually watching it in, instead
  /// of needing to find it again in their profile grid — the same
  /// owner-only, RLS-enforced PostService.deletePost profile_screen.dart
  /// already uses, just reachable from here too.
  Future<void> _deletePost(Post post) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Delete this episode?'),
        content: const Text("This can't be undone — it'll be removed from the Dramas feed for everyone."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await PostService.deletePost(post);
      if (!mounted) return;
      setState(() => _posts = _posts.where((p) => p.id != post.id).toList());
      if (_posts.isEmpty) {
        Navigator.of(context).pop();
        return;
      }
      if (_currentIndex >= _posts.length) {
        setState(() => _currentIndex = _posts.length - 1);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_pageController.hasClients) _pageController.jumpToPage(_currentIndex);
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete: ${friendlyErrorMessage(e)}')),
      );
    }
  }

  /// Unlock with ads: the viewer picks how many episodes (from this one on), watches the
  /// ads back to back, and each pair of Google-verified ads unlocks the next episode.
  Future<void> _unlockWithAds(Post post) async {
    if (!await GuestGate.allow(context, action: 'unlock this episode')) return;
    if (!mounted) return;
    final start = _posts.indexWhere((p) => p.id == post.id);
    final viewer = SupabaseService.currentUserId;
    final locked = [
      for (final p in _posts.skip(start < 0 ? 0 : start))
        if (isEpisodeLocked(p, viewerId: viewer)) p,
    ];
    if (locked.isEmpty) return;
    final unlockedIds = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _AdUnlockSheet(episodes: locked),
    );
    if (!mounted || unlockedIds == null || unlockedIds.isEmpty) return;
    setState(() {
      _posts = _posts.map((p) => unlockedIds.contains(p.id) ? p.copyWith(unlockedByMe: true) : p).toList();
    });
    final n = unlockedIds.length;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Unlocked $n episode${n == 1 ? '' : 's'} — enjoy! 🎬')),
    );
  }

  Future<void> _unlockEpisode(Post post) async {
    if (!await GuestGate.allow(context, action: 'unlock this episode')) return;
    try {
      await SeriesService.unlockEpisode(post.id);
      if (!mounted) return;
      setState(() {
        _posts = _posts.map((p) => p.id == post.id ? p.copyWith(unlockedByMe: true) : p).toList();
      });
    } on InsufficientCoinsException catch (e) {
      if (!mounted) return;
      // Offers watch-an-ad / buy coins / earn coins — not just a "you
      // can't afford this" snackbar — since unlocking an episode is a
      // real purchase moment, not a soft AI-feature gate.
      await showInsufficientCoinsSheet(context, e);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyErrorMessage(e))),
      );
    }
  }

  void _openComments(Post post) {
    // A bottom sheet, not a full navigation — the video keeps playing
    // and visible behind it, matching what commenting looks like on
    // every other short-form feed. A full-screen route here previously
    // left the video mounted and still playing underneath, invisible,
    // since the PageView itself never changed pages.
    showCommentsSheet(
      context,
      post,
      onCommentAdded: () {
        if (!mounted) return;
        setState(() {
          _posts = _posts
              .map((p) => p.id == post.id ? p.copyWith(commentCount: p.commentCount + 1) : p)
              .toList();
        });
      },
    );
  }

  Future<void> _share(Post post) => ShareLinks.sharePost(post);

  void _openProfile(Post post) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ProfileScreen(userId: post.userId)),
    );
  }

  /// Auto-advance to the next episode/video once the current one finishes
  /// — see _VideoPage.autoAdvance. A no-op past the last item; a locked
  /// next episode still advances into view (showing its own paywall),
  /// same as swiping to it manually would.
  void _advanceToNext(int fromIndex) {
    final next = fromIndex + 1;
    if (next >= _posts.length || !_pageController.hasClients) return;
    _pageController.animateToPage(
      next,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : _posts.isEmpty
              ? const _EmptyVideoState()
              : PageView.builder(
                  controller: _pageController,
                  scrollDirection: Axis.vertical,
                  // Builds one page either side of the visible one, so the next video is
                  // already downloading (paused, muted to the user) while this one plays and
                  // starts at once on swipe, instead of loading from scratch after it.
                  allowImplicitScrolling: true,
                  itemCount: _posts.length,
                  onPageChanged: _onPageChanged,
                  itemBuilder: (ctx, i) {
                    final post = _posts[i];
                    final locked = isEpisodeLocked(post, viewerId: SupabaseService.currentUserId);
                    final nextPost = i + 1 < _posts.length ? _posts[i + 1] : null;
                    final nextLocked = nextPost != null
                        ? isEpisodeLocked(nextPost, viewerId: SupabaseService.currentUserId)
                        : false;
                    return _VideoPage(
                      key: ValueKey(post.id),
                      post: post,
                      isActive: i == _currentIndex,
                      isLocked: locked,
                      nextPost: nextPost,
                      nextLocked: nextLocked,
                      // Only auto-advance within a series — the global
                      // video feed keeps its existing loop-forever
                      // behavior, since there's no "next episode" to
                      // queue up outside a series context.
                      autoAdvance: widget.seriesId != null,
                      onEnded: () => _advanceToNext(i),
                      onLike: () => _like(post),
                      onComment: () => _openComments(post),
                      onShare: () => _share(post),
                      onOpenProfile: () => _openProfile(post),
                      onBecameActive: () => _recordView(post),
                      onUnlock: () => _unlockEpisode(post),
                      onUnlockWithAds: () => _unlockWithAds(post),
                      onDelete: () => _deletePost(post),
                    );
                  },
                ),
    );
  }
}

class _VideoPage extends StatefulWidget {
  final Post post;
  final bool isActive;
  final bool isLocked;
  // The next page in the PageView, if any — used only to populate the
  // Up Next overlay (thumbnail/title/lock state); playback itself
  // never touches this post directly.
  final Post? nextPost;
  final bool nextLocked;
  // When true, this page doesn't loop — it plays once and calls onEnded,
  // which the parent uses to auto-advance to the next page. Only set for
  // series playback; the general video feed keeps looping.
  final bool autoAdvance;
  final VoidCallback? onEnded;
  final VoidCallback? onLike;
  final VoidCallback onComment;
  final VoidCallback onShare;
  final VoidCallback onOpenProfile;
  final VoidCallback onBecameActive;
  final Future<void> Function() onUnlock;
  final Future<void> Function() onUnlockWithAds;
  final VoidCallback onDelete;

  const _VideoPage({
    super.key,
    required this.post,
    required this.isActive,
    required this.isLocked,
    this.nextPost,
    this.nextLocked = false,
    this.autoAdvance = false,
    this.onEnded,
    required this.onLike,
    required this.onComment,
    required this.onShare,
    required this.onOpenProfile,
    required this.onBecameActive,
    required this.onUnlock,
    required this.onUnlockWithAds,
    required this.onDelete,
  });

  @override
  State<_VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<_VideoPage> {
  VideoPlayerController? _controller;
  bool _ended = false;
  bool _muted = false;
  bool _liked = false;
  bool _initError = false;
  bool _unlocking = false;
  bool _showUpNext = false;
  // True only during the one-retry window in _initialize() below, after
  // the stored URL has already failed but before the corrected one has
  // been tried — keeps build() showing a spinner through that gap
  // instead of flashing the terminal "Video unavailable" state for a
  // retry that's still genuinely in flight.
  bool _retrying = false;
  // Set only if this page's own self-heal poll (see _pollBunnyStatus)
  // finds the video failed — post.isVideoFailed itself can't change
  // here, since widget.post is the same immutable snapshot this page
  // was built with.
  bool _processingFailedOverride = false;

  // Throttles WatchProgressService writes — video_player's listener
  // fires far too often (essentially every frame) to persist on every
  // callback without hammering SharedPreferences.
  Duration? _lastSavedPosition;
  static const _savePositionInterval = Duration(seconds: 3);

  Future<void> _handleUnlock() async {
    if (_unlocking) return;
    setState(() => _unlocking = true);
    try {
      await widget.onUnlock();
    } finally {
      if (mounted) setState(() => _unlocking = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _liked = widget.post.likedByMe;
    // A locked episode never even downloads its video — there's
    // nothing to play until it's unlocked, so starting a network
    // fetch for it would just waste bandwidth on content the viewer
    // can't watch yet. A Bunny-hosted video still mid-encode has no
    // file behind its playback URL yet either — starting a fetch for
    // it would just fail, so this waits for the background poll kicked
    // off at upload time (see PostService.updateVideoStatus) to flip
    // video_status before ever trying to play it.
    if (!widget.isLocked && !widget.post.isVideoProcessing && !widget.post.isVideoFailed) {
      _initialize();
    } else if (!widget.isLocked && widget.post.isVideoProcessing && widget.post.bunnyVideoId != null) {
      _pollBunnyStatus();
    }
    if (widget.isActive) widget.onBecameActive();
  }

  /// Self-heals a video stuck showing "Processing…" — the one-shot poll
  /// kicked off at upload time (see the upload screens' _submit) only
  /// runs while that screen's browser tab stays open and active; if the
  /// creator navigated away, closed the tab, or a mobile browser
  /// suspended it before Bunny finished encoding, video_status never
  /// got flipped, and this post would otherwise stay stuck showing
  /// "Processing…" forever even though Bunny itself finished within a
  /// minute or two. Re-checking here means the next time *anyone* opens
  /// this video, it self-heals instead of depending on that first tab.
  Future<void> _pollBunnyStatus() async {
    final videoId = widget.post.bunnyVideoId;
    if (videoId == null) return;
    try {
      final status = await BunnyStreamService.waitForReady(videoId);
      if (!mounted || status == null) return;
      await PostService.updateVideoStatus(
        widget.post.id,
        status.failed ? 'failed' : 'ready',
        mediaUrl: status.failed ? null : status.playbackUrl,
      );
      if (!mounted) return;
      if (status.failed) {
        setState(() => _processingFailedOverride = true);
      } else {
        // Bunny's done — start playback immediately instead of making
        // this viewer back out and reopen the video. Uses status's own
        // freshly-resolved URL, not widget.post.mediaUrl — that's still
        // the pre-encode guess from upload time (see _initialize's own
        // comment on _resolvedMediaUrl).
        _initialize(urlOverride: status.playbackUrl);
      }
    } catch (_) {
      // Best-effort — worst case this viewer still sees "Processing…"
      // and the next person to open it tries again.
    }
  }

  Future<void> _initialize({String? urlOverride}) async {
    final url = urlOverride ?? widget.post.mediaUrl;
    if (url == null || url.trim().isEmpty) {
      if (mounted) setState(() => _initError = true);
      return;
    }

    // Where this viewer stopped last time (a database read): started now so it runs while
    // the video loads, instead of adding a second wait after it.
    final resumeLookup = WatchProgressService.getPosition(widget.post.id);

    var controller = VideoPlayerController.networkUrl(Uri.parse(url));

    try {
      await controller.initialize();
    } catch (_) {
      await controller.dispose();
      // The URL stored on this post (play_<N>p.mp4 at a fixed guessed
      // resolution — see bunny_stream.py's own module comment) 404s
      // whenever Bunny encoded this video's source below that
      // resolution, which never self-heals on its own: video_status
      // already reads "ready", so the self-heal poll above never even
      // runs for it. Bunny itself finished long ago, so re-checking
      // status now returns a corrected URL at a resolution this video
      // actually has (bunny_stream.py's _pick_resolution) — worth one
      // retry before calling this video genuinely broken.
      final videoId = widget.post.bunnyVideoId;
      if (videoId == null) {
        if (mounted) setState(() => _initError = true);
        return;
      }
      if (mounted) setState(() => _retrying = true);
      BunnyVideoStatus? status;
      try {
        status = await BunnyStreamService.getStatus(videoId);
      } catch (_) {}
      if (status == null || !status.ready || status.playbackUrl == url) {
        if (mounted) setState(() { _retrying = false; _initError = true; });
        return;
      }
      unawaited(PostService.updateVideoStatus(widget.post.id, 'ready', mediaUrl: status.playbackUrl));
      controller = VideoPlayerController.networkUrl(Uri.parse(status.playbackUrl));
      try {
        await controller.initialize();
      } catch (_) {
        await controller.dispose();
        if (mounted) setState(() { _retrying = false; _initError = true; });
        return;
      }
      if (mounted) setState(() => _retrying = false);
    }

    try {
      await controller.setLooping(!widget.autoAdvance);
      await controller.setVolume(_muted ? 0 : 1);

      // Resume where this viewer left off, if anywhere — local-only
      // (see WatchProgressService), so this is per-device, not synced.
      final resumeAt = await resumeLookup;
      if (resumeAt != null && resumeAt < controller.value.duration) {
        await controller.seekTo(resumeAt);
        _lastSavedPosition = resumeAt;
      }

      // Backfills width/height the first time this post is actually
      // opened, if nothing has ever done it before — see
      // VideoMetadataService.ensureDimensions's own comment for why
      // this is needed even for a video that's already playing fine.
      VideoMetadataService.ensureDimensions(widget.post);
      VideoMetadataService.ensureThumbnail(widget.post);
    } catch (_) {
      // The video genuinely failed to load — this is the real
      // "unavailable" case.
      await controller.dispose();
      if (mounted) setState(() => _initError = true);
      return;
    }

    if (!mounted) {
      await controller.dispose();
      return;
    }

    controller.addListener(_videoListener);
    setState(() => _controller = controller);

    if (widget.isActive) {
      try {
        await controller.play();
      } catch (_) {
        // A loaded-and-ready video can still fail to autoplay — a
        // browser blocking unmuted autoplay without a fresh-enough user
        // gesture is the common case on web. That's not the same
        // failure as never loading at all: the video stays set, just
        // paused, so it shows normally and the existing tap-to-play
        // control (_togglePlay) still starts it. Previously this was
        // caught by the same block as the load itself and the whole
        // video was thrown away as "unavailable" even though it had
        // already loaded fine.
      }
    }
  }

  void _videoListener() {
    if (!mounted) return;
    final c = _controller;
    if (c != null && c.value.isInitialized && c.value.duration > Duration.zero) {
      _maybeSavePosition(c.value.position, c.value.duration);

      // video_player has no explicit "completed" event — a non-looping
      // controller just pauses once it reaches the end, so that's the
      // signal to treat as "this episode is over" and fire onEnded once
      // (or, if there's a next episode queued, show Up Next instead of
      // advancing immediately/silently).
      if (widget.autoAdvance && !_ended) {
        final remaining = c.value.duration - c.value.position;
        if (remaining <= const Duration(milliseconds: 200)) {
          _ended = true;
          unawaited(WatchProgressService.clearPosition(widget.post.id));
          if (widget.nextPost != null) {
            _showUpNext = true;
          } else {
            widget.onEnded?.call();
          }
        }
      }
    }
    setState(() {});
  }

  void _maybeSavePosition(Duration position, Duration duration) {
    final last = _lastSavedPosition;
    if (last != null && (position - last).abs() < _savePositionInterval) return;
    _lastSavedPosition = position;
    unawaited(WatchProgressService.savePosition(widget.post, position, duration));
  }

  @override
  void didUpdateWidget(covariant _VideoPage oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.post.id == oldWidget.post.id &&
        widget.post.likedByMe != oldWidget.post.likedByMe) {
      _liked = widget.post.likedByMe;
    }

    if (widget.isActive && !oldWidget.isActive) {
      widget.onBecameActive();
    }

    final justUnlocked = oldWidget.isLocked && !widget.isLocked;
    final justFinishedProcessing =
        (oldWidget.post.isVideoProcessing || oldWidget.post.isVideoFailed) &&
            !widget.post.isVideoProcessing &&
            !widget.post.isVideoFailed;
    if ((justUnlocked || justFinishedProcessing) &&
        _controller == null &&
        !widget.isLocked &&
        !widget.post.isVideoProcessing &&
        !widget.post.isVideoFailed) {
      // Either just unlocked (nothing was ever downloaded while
      // locked) or Bunny just finished encoding this video (see the
      // matching guard in initState) — either way, this is the first
      // real chance to start playback.
      _initialize();
    }

    final c = _controller;
    if (c == null || !c.value.isInitialized) return;

    if (widget.isActive && !oldWidget.isActive) {
      c.play();
    } else if (!widget.isActive && oldWidget.isActive) {
      c.pause();
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_videoListener);
    final c = _controller;
    if (c != null && c.value.isInitialized && c.value.duration > Duration.zero && !_ended) {
      // Fire-and-forget final flush — dispose() can't be async, and a
      // position saved 3 seconds ago (the throttle window) is close
      // enough that losing this exact write isn't worth blocking on.
      // forceServerSync bypasses the (much coarser) server throttle —
      // this is the one moment a synced value has to be current, since
      // a different device reopening this episode next reads the
      // server row as its source of truth (see WatchProgressService
      // .getPosition).
      unawaited(WatchProgressService.savePosition(
        widget.post, c.value.position, c.value.duration,
        forceServerSync: true,
      ));
    }
    _controller?.dispose();
    super.dispose();
  }

  void _handleLike() {
    setState(() {
      _liked = !_liked;
    });
    widget.onLike?.call();
  }

  void _togglePlay() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (c.value.isPlaying) {
      c.pause();
    } else {
      c.play();
    }
    setState(() {});
  }

  void _toggleMute() {
    setState(() => _muted = !_muted);
    _controller?.setVolume(_muted ? 0 : 1);
  }

  String _time(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final c = _controller;
    final ready = c?.value.isInitialized == true;

    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.isLocked ? null : _togglePlay,
          onDoubleTap: widget.isLocked ? null : _handleLike,
          child: Container(
            color: Colors.black,
            alignment: Alignment.center,
            // Full-bleed, edge-to-edge playback (BoxFit.cover) instead of
            // a letterboxed AspectRatio box — matches every other
            // short-form/drama app. VideoPlayer has no fit param of its
            // own, so FittedBox + a SizedBox at the video's natural size
            // is the standard way to get cover behavior from it.
            child: widget.isLocked
                ? _lockedMedia()
                : ready
                    ? FittedBox(
                        // Landscape content (movies/full-length shows,
                        // or any video whose own decoded frame is wider
                        // than it is tall — e.g. a standalone upload
                        // that was never attached to a series, so
                        // series.orientation isn't there to flag it)
                        // shows full-frame letterboxed instead of
                        // getting cropped to fill a vertical screen —
                        // the black Container behind this already
                        // provides the letterbox bars. Checking the
                        // controller's own decoded size (not just
                        // post.isLandscapeVideo) is what actually
                        // catches that second case: a 640x354 video
                        // posted outside the Studio/series flow has no
                        // series row to carry an orientation at all, so
                        // the metadata-only check cropped ~75% of its
                        // width away trying to cover a vertical screen.
                        // Vertical dramas/shorts (aspectRatio <= 1) keep
                        // the existing edge-to-edge cover behavior,
                        // unchanged.
                        fit: (post.isLandscapeVideo || c!.value.aspectRatio > 1.0) ? BoxFit.contain : BoxFit.cover,
                        child: SizedBox(
                          width: c!.value.size.width,
                          height: c.value.size.height,
                          child: VideoPlayer(c),
                        ),
                      )
                    : post.isVideoProcessing && !_processingFailedOverride
                        ? _videoProcessing()
                        : post.isVideoFailed || _processingFailedOverride
                            ? _videoError(message: 'This video failed to process')
                            // Checked before the thumbnail below on purpose:
                            // a Bunny-hosted thumbnail can 404 for the exact
                            // same reason the video URL does (see
                            // _initialize's own comment) while this retry is
                            // still in flight, and CachedNetworkImage's own
                            // errorWidget would otherwise flash the same
                            // "Video unavailable" state for a video that's
                            // actually about to start playing fine.
                            : _retrying
                                ? const Center(
                                    child: CircularProgressIndicator(color: AppColors.primary),
                                  )
                                : post.thumbnailUrl != null
                                ? RetryableNetworkImage(
                                    imageUrl: post.thumbnailUrl!,
                                    fit: BoxFit.cover,
                                    // Full-screen here, so a bigger cap
                                    // than a grid tile's, but still far
                                    // below an oversized source asset.
                                    memCacheWidth: 1080,
                                    placeholder: (_, __) => const Center(
                                      child: CircularProgressIndicator(
                                        color: AppColors.primary,
                                      ),
                                    ),
                                    errorWidget: (_, __, ___) => _videoError(),
                                  )
                                : _initError
                                    ? _videoError()
                                    : const Center(
                                        child: CircularProgressIndicator(
                                          color: AppColors.primary,
                                        ),
                                      ),
          ),
        ),

        // Paused: a play icon (tap anywhere resumes). Stalled mid-video: a spinner.
        if (!widget.isLocked && ready && !_showUpNext)
          IgnorePointer(
            child: Center(
              child: c!.value.isBuffering
                  ? const CircularProgressIndicator(color: Colors.white70)
                  : !c.value.isPlaying
                      ? Container(
                          padding: const EdgeInsets.all(14),
                          decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                          child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 56),
                        )
                      : const SizedBox.shrink(),
            ),
          ),

        if (post.isEpisode)
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: _SeriesBadge(post: post),
              ),
            ),
          ),

        SafeArea(
          child: Align(
            alignment: Alignment.topLeft,
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ),

        SafeArea(
          child: Align(
            alignment: Alignment.topRight,
            child: IconButton(
              icon: Icon(
                _muted ? Icons.volume_off : Icons.volume_up,
                color: Colors.white,
              ),
              onPressed: _toggleMute,
            ),
          ),
        ),

        // Creator and caption.
        Positioned(
          left: 14,
          right: 82,
          bottom: 36,
          child: SafeArea(
            top: false,
            child: GestureDetector(
              onTap: widget.onOpenProfile,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: AppColors.surfaceBorder,
                        backgroundImage: post.authorAvatarUrl != null
                            ? CachedNetworkImageProvider(
                                post.authorAvatarUrl!,
                              )
                            : null,
                        child: post.authorAvatarUrl == null
                            ? Text(
                                (post.authorDisplayName ?? '?')[0]
                                    .toUpperCase(),
                              )
                            : null,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          '@${post.authorUsername ?? 'unknown'}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (post.caption.trim().isNotEmpty) ...[
                    const SizedBox(height: 7),
                    Text(
                      post.caption,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        height: 1.3,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),

        // Like/comment/share actions.
        Positioned(
          right: 12,
          bottom: 38,
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                _likeAction(post),
                const SizedBox(height: 18),
                _ActionIcon(
                  icon: Icons.visibility_outlined,
                  color: Colors.white,
                  label: '${post.viewCount}',
                  onTap: null,
                ),
                const SizedBox(height: 18),
                _ActionIcon(
                  icon: Icons.mode_comment_outlined,
                  color: Colors.white,
                  label: '${post.commentCount}',
                  onTap: widget.onComment,
                ),
                const SizedBox(height: 18),
                _ActionIcon(
                  icon: Icons.share_outlined,
                  color: Colors.white,
                  label: 'Share',
                  onTap: widget.onShare,
                ),
                if (post.userId == SupabaseService.currentUserId) ...[
                  const SizedBox(height: 18),
                  _ActionIcon(
                    icon: Icons.delete_outline,
                    color: Colors.white,
                    label: 'Delete',
                    onTap: widget.onDelete,
                  ),
                ],
              ],
            ),
          ),
        ),

        // Playback controls.
        if (ready)
          Positioned(
            left: 10,
            right: 10,
            bottom: 10,
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Text(
                    _time(c!.value.position),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                    ),
                  ),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 2,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 5,
                        ),
                        overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 10,
                        ),
                      ),
                      child: Slider(
                        min: 0,
                        max: c.value.duration.inMilliseconds
                            .toDouble()
                            .clamp(1, double.infinity),
                        value: c.value.position.inMilliseconds
                            .toDouble()
                            .clamp(
                              0,
                              c.value.duration.inMilliseconds.toDouble(),
                            ),
                        activeColor: AppColors.primary,
                        inactiveColor: Colors.white30,
                        onChanged: (v) => c.seekTo(
                          Duration(milliseconds: v.round()),
                        ),
                      ),
                    ),
                  ),
                  Text(
                    _time(c.value.duration),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ),

        if (_showUpNext && widget.nextPost != null)
          Positioned.fill(
            child: UpNextOverlay(
              nextPost: widget.nextPost!,
              nextLocked: widget.nextLocked,
              onCancel: () => setState(() => _showUpNext = false),
              onAdvance: () {
                setState(() => _showUpNext = false);
                widget.onEnded?.call();
              },
              onBackToSeries: () => Navigator.of(context).pop(),
            ),
          ),
      ],
    );
  }

  /// Its own widget (rather than the generic _ActionIcon) so the heart can
  /// "pop" on tap, matching the same feedback the feed's PostCard gives.
  Widget _likeAction(Post post) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onLike,
      child: Column(
        children: [
          TweenAnimationBuilder<double>(
            key: ValueKey(_liked),
            tween: Tween(begin: _liked ? 1.4 : 1.0, end: 1.0),
            duration: const Duration(milliseconds: 280),
            curve: Curves.elasticOut,
            builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
            child: Icon(
              _liked ? Icons.favorite : Icons.favorite_border,
              color: _liked ? AppColors.secondary : Colors.white,
              size: 30,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${post.likeCount + (_liked == post.likedByMe ? 0 : (_liked ? 1 : -1))}',
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _videoError({String message = 'Video unavailable'}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.error_outline,
          color: Colors.white54,
          size: 44,
        ),
        const SizedBox(height: 8),
        Text(
          message,
          style: const TextStyle(color: Colors.white70),
        ),
      ],
    );
  }

  /// Bunny Stream still needs a little time to encode a just-uploaded
  /// video — the playback URL is real (it's deterministic from the
  /// video id, see bunny_stream.py) but there's no file behind it yet,
  /// so this shows the thumbnail everyone already sees (small local
  /// JPEG uploaded to Supabase Storage regardless of provider) rather
  /// than attempting a fetch that would just 404. Flips to the real
  /// player on its own once the background poll started at upload time
  /// updates this post's video_status (see didUpdateWidget above) —
  /// nothing here needs to poll itself.
  Widget _videoProcessing() {
    final thumbnailUrl = widget.post.thumbnailUrl;
    return Stack(
      fit: StackFit.expand,
      alignment: Alignment.center,
      children: [
        if (thumbnailUrl != null)
          RetryableNetworkImage(
            imageUrl: thumbnailUrl,
            fit: BoxFit.cover,
            memCacheWidth: 1080,
            errorWidget: (_, __, ___) => const SizedBox.shrink(),
          ),
        Container(color: Colors.black.withOpacity(0.4)),
        const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
            ),
            SizedBox(height: 10),
            Text('Processing video…', style: TextStyle(color: Colors.white70)),
          ],
        ),
      ],
    );
  }

  /// A blurred thumbnail behind an unlock paywall — the episode's
  /// video was never even downloaded (see initState), so this is
  /// deliberately the thumbnail, not a frame of the real video.
  Widget _lockedMedia() {
    final post = widget.post;
    final price = post.seriesCoinPrice ?? kDefaultEpisodeCoinPrice;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (post.thumbnailUrl != null)
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: RetryableNetworkImage(
              imageUrl: post.thumbnailUrl!,
              fit: BoxFit.cover,
              // Blurred anyway, so full source resolution buys nothing
              // visually.
              memCacheWidth: 1080,
              errorWidget: (_, __, ___) => Container(color: Colors.black),
            ),
          )
        else
          Container(color: Colors.black),
        Container(color: Colors.black.withOpacity(0.45)),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.12),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white24),
                ),
                child: const Icon(Icons.lock_outline, color: Colors.white, size: 26),
              ),
              const SizedBox(height: 14),
              Text(
                'Episode ${post.episodeNumber ?? ''} is locked',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _handleUnlock,
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.secondary),
                icon: _unlocking
                    ? const SizedBox(
                        height: 14, width: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                      )
                    : const Icon(Icons.monetization_on, size: 16, color: Colors.black),
                label: Text(
                  _unlocking ? 'Unlocking...' : 'Unlock for $price coins',
                  style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w700),
                ),
              ),
              if (!kIsWeb) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _unlocking ? null : widget.onUnlockWithAds,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white54),
                  ),
                  icon: const Icon(Icons.smart_display_outlined, size: 18),
                  label: const Text('Watch 2 ads to unlock', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ],
              // Premium can't be bought in the Android app (Google Play), so it isn't offered there.
              if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) ...[
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SubscribeScreen()),
                  ),
                  child: const Text(
                    'or go Premium for unlimited episodes',
                    style: TextStyle(color: Colors.white70, fontSize: 12.5),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Choose how many episodes to unlock with ads, then watch them back to back.
/// Pops with the ids of the episodes it unlocked (possibly fewer than chosen if
/// the viewer stops, no ad is available, or today's limit is reached; tickets
/// already earned are kept for next time).
class _AdUnlockSheet extends StatefulWidget {
  final List<Post> episodes;            // locked episodes, starting with the one on screen
  const _AdUnlockSheet({required this.episodes});

  @override
  State<_AdUnlockSheet> createState() => _AdUnlockSheetState();
}

class _AdUnlockSheetState extends State<_AdUnlockSheet> {
  int? _tickets;
  int _perEpisode = 2;
  int _adsLeftToday = 30;
  DateTime? _nextFreeAt;
  String? _error;
  bool _running = false;
  bool _stop = false;
  String _status = '';
  final Set<String> _unlocked = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final t = await SeriesService.adTickets();
      if (!mounted) return;
      setState(() {
        _tickets = t.tickets;
        _perEpisode = t.adsPerEpisode;
        _adsLeftToday = (t.dailyCap - t.adsToday).clamp(0, t.dailyCap);
        _nextFreeAt = t.nextFreeAt;
      });
    } catch (e) {
      if (mounted) setState(() => _error = friendlyErrorMessage(e));
    }
  }

  String _comeBack() {
    final at = _nextFreeAt;
    if (at == null) return 'Come back in a few hours to unlock more.';
    final mins = at.difference(DateTime.now()).inMinutes;
    if (mins <= 1) return 'You can unlock more now — reopen this.';
    final hours = (mins / 60).round();
    return mins >= 90 ? 'Come back in about $hours hours to unlock more.' : 'Come back in about $mins minutes to unlock more.';
  }

  int _adsFor(int episodes) => (episodes * _perEpisode - (_tickets ?? 0)).clamp(0, 1 << 30);

  Future<void> _run(int count) async {
    setState(() {
      _running = true;
      _stop = false;
      _error = null;
    });
    var tickets = _tickets ?? 0;
    final targets = widget.episodes.take(count).toList();
    final totalAds = _adsFor(count);
    var adsShown = 0;
    try {
      for (final ep in targets) {
        while (tickets < _perEpisode) {
          if (_stop) {
            if (mounted) Navigator.of(context).pop(_unlocked);
            return;
          }
          setState(() => _status = 'Ad ${adsShown + 1} of $totalAds');
          final earned = await RewardedAdService.showForEpisodeTicket();
          if (earned == null) {
            if (mounted) {
              setState(() => _error = 'No ad available right now, or it was closed early. Ads you finished are saved.');
            }
            return;
          }
          adsShown++;
          tickets += earned;
          if (mounted) setState(() => _tickets = tickets);
        }
        if (mounted) setState(() => _status = 'Unlocking episode ${ep.episodeNumber ?? ''}...');
        if (await SeriesService.unlockEpisodeWithAds(ep.id)) {
          tickets -= _perEpisode;
          _unlocked.add(ep.id);
          if (mounted) setState(() => _tickets = tickets);
        }
      }
      if (mounted) Navigator.of(context).pop(_unlocked);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyErrorMessage(e));
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final available = widget.episodes.length;
    final options = <int>{1, 3, 5, 10, 15, if (available <= 15) available}
        .where((n) => n >= 1 && n <= available)
        .toList()
      ..sort();
    return PopScope(
      canPop: !_running,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Unlock with ads', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(
                '$_perEpisode ads unlock 1 episode. Watch them back to back to unlock several at once.'
                '${(_tickets ?? 0) > 0 ? ' You have ${_tickets!} saved ad${_tickets == 1 ? '' : 's'}.' : ''}',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 16),
              if (_tickets == null && _error == null)
                const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
              else if (_running) ...[
                Row(children: [
                  const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 12),
                  Expanded(child: Text(_status)),
                ]),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => setState(() => _stop = true),
                  child: const Text('Stop after this ad'),
                ),
              ] else ...[
                for (final n in options)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: OutlinedButton(
                      onPressed: _adsFor(n) > _adsLeftToday ? null : () => _run(n),
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                      child: Text(
                        n == 1
                            ? 'This episode · ${_adsFor(n)} ad${_adsFor(n) == 1 ? '' : 's'}'
                            : '$n episodes · ${_adsFor(n)} ads',
                      ),
                    ),
                  ),
                Text(
                  _adsLeftToday > 0
                      ? 'You can unlock up to ${_adsLeftToday ~/ _perEpisode} more episode'
                          '${_adsLeftToday ~/ _perEpisode == 1 ? '' : 's'} with ads right now. More open up a few hours later.'
                      : 'You\'ve unlocked the most episodes with ads for now. ${_comeBack()}',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
              ],
              if (_unlocked.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Unlocked so far: ${_unlocked.length}', style: const TextStyle(color: AppColors.secondary)),
              ],
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
                if (_unlocked.isNotEmpty)
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(_unlocked),
                    child: const Text('Done'),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyVideoState extends StatelessWidget {
  const _EmptyVideoState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.videocam_off_outlined, color: Colors.white54, size: 28),
          ),
          const SizedBox(height: 16),
          const Text(
            'No videos yet',
            style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// The one visual marker that tells an AI Short Drama episode apart
/// from an ordinary video in the same feed — a small sparkle pill
/// naming the series and episode number.
class _SeriesBadge extends StatelessWidget {
  final Post post;
  const _SeriesBadge({required this.post});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.45),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.secondary.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.auto_awesome, size: 12, color: AppColors.secondary),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              '${post.seriesTitle ?? 'Short Drama'} · Ep ${post.episodeNumber ?? ''}',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback? onTap;

  const _ActionIcon({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        children: [
          Icon(icon, color: color, size: 30),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
