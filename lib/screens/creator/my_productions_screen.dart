import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../models/series.dart';
import '../../services/creator_download_service.dart';
import '../../services/file_saver_io.dart' if (dart.library.html) '../../services/file_saver_web.dart' as saver;
import '../../services/post_service.dart';
import '../../services/series_service.dart';
import '../../theme/app_theme.dart';
import '../post/post_detail_screen.dart';
import '../post/series_detail_screen.dart';

/// My Productions: every series and video the creator owns, with
/// downloads for posting anywhere. Downloading never publishes, deletes
/// or changes anything — Viyo keeps its copy.
class MyProductionsScreen extends StatefulWidget {
  const MyProductionsScreen({super.key});

  @override
  State<MyProductionsScreen> createState() => _MyProductionsScreenState();
}

class _DownloadState {
  double? progress; // null while preparing, 0..1 when known
  bool running = false;
  bool done = false;
  String? error;
  String? savedPath;
  String? quality;
  CancelToken? cancel;
}

class _MyProductionsScreenState extends State<MyProductionsScreen> {
  List<Production>? _items;
  String? _error;
  bool _loading = true;
  final Map<String, _DownloadState> _downloads = {};
  final Set<String> _expanded = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final d in _downloads.values) {
      d.cancel?.cancel();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await CreatorDownloadService.myProductions();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  // ---------------------------------------------------------------- actions

  Future<void> _download(ProductionEpisode ep, {bool thumbnail = false}) async {
    final key = thumbnail ? '${ep.postId}:thumb' : ep.postId;
    final state = _downloads.putIfAbsent(key, _DownloadState.new);
    if (state.running) return;
    setState(() {
      state
        ..running = true
        ..done = false
        ..error = null
        ..progress = null
        ..cancel = CancelToken();
    });
    DownloadLink? link;
    try {
      final path = await saver.saveFromUrl(
        freshUrl: () async {
          link = thumbnail
              ? await CreatorDownloadService.thumbnailLink(ep.postId)
              : await CreatorDownloadService.videoLink(ep.postId);
          if (mounted) setState(() => state.quality = link!.quality);
          return (link!.url, link!.fileName);
        },
        cancelToken: state.cancel,
        onProgress: (got, total) {
          if (!mounted) return;
          setState(() => state.progress = total == null || total == 0 ? null : got / total);
        },
      );
      if (!mounted) return;
      setState(() {
        state
          ..running = false
          ..done = true
          ..savedPath = path;
      });
      if (saver.savesInBrowser) {
        _snack(thumbnail ? 'Thumbnail download started.' : 'Download started — check your browser downloads.');
      } else if (path != null) {
        await saver.shareSavedFile(path, thumbnail ? 'image/jpeg' : 'video/mp4');
      }
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        state
          ..running = false
          ..error = CancelToken.isCancel(e) ? 'Cancelled' : 'Connection lost. Tap retry to continue.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        state
          ..running = false
          ..error = e.toString().replaceFirst('Exception: ', '').replaceFirst('FileSystemException: ', '');
      });
    }
  }

  Future<void> _downloadAll(Production p) async {
    final eps = p.episodes.where((e) => e.downloadable).toList();
    for (final ep in eps) {
      if (!mounted) return;
      await _download(ep);
      if (saver.savesInBrowser) await Future.delayed(const Duration(milliseconds: 1200));
    }
  }

  Future<void> _open(Production p) async {
    try {
      if (p.isSeries) {
        final s = await SeriesService.getSeries(p.id);
        if (s == null || !mounted) return;
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => SeriesDetailScreen(series: s)));
      } else {
        await _preview(p.episodes.first);
      }
    } catch (_) {
      _snack("Couldn't open it right now.");
    }
  }

  Future<void> _preview(ProductionEpisode ep) async {
    final posts = await PostService.getPostsByIds([ep.postId]);
    if (posts.isEmpty || !mounted) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => PostDetailScreen(post: posts.first)));
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  // ---------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('My Productions'),
        backgroundColor: AppColors.background,
        actions: [IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh), tooltip: 'Refresh')],
      ),
      body: RefreshIndicator(onRefresh: _load, child: _body()),
    );
  }

  Widget _body() {
    if (_loading && _items == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _items == null) {
      return ListView(padding: const EdgeInsets.all(24), children: [
        const SizedBox(height: 60),
        const Icon(Icons.cloud_off, size: 40, color: AppColors.textMuted),
        const SizedBox(height: 12),
        Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary)),
        const SizedBox(height: 16),
        Center(child: OutlinedButton(onPressed: _load, child: const Text('Try again'))),
      ]);
    }
    final items = _items ?? [];
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
          children: [
            const _RightsCard(),
            const SizedBox(height: 12),
            if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48, horizontal: 16),
                child: Column(children: [
                  Icon(Icons.movie_creation_outlined, size: 44, color: AppColors.textMuted),
                  SizedBox(height: 12),
                  Text('No productions yet', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  SizedBox(height: 6),
                  Text('Upload a drama, film or video and it will show up here, ready to download.',
                      textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                ]),
              ),
            for (final p in items) ...[_productionCard(p), const SizedBox(height: 10)],
          ],
        ),
      ),
    );
  }

  String _typeLabel(Production p) {
    if (!p.isSeries) return 'Video';
    return kContentTypeLabels[p.contentType ?? kContentTypeShortDrama] ?? 'Series';
  }

  String _watchSummary(Production p) {
    if (p.publicEpisodeCount == 0) return 'Private';
    if (p.publicEpisodeCount == p.episodeCount) return 'On Viyo Watch';
    return '${p.publicEpisodeCount} of ${p.episodeCount} on Viyo Watch';
  }

  Widget _productionCard(Production p) {
    final open = _expanded.contains(p.id);
    final downloadable = p.episodes.where((e) => e.downloadable).length;
    final single = !p.isSeries ? p.episodes.first : null;
    return Container(
      decoration: AppTheme.card(),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _thumb(p.thumbnailUrl, vertical: p.orientation != kOrientationLandscape),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  _chip(_typeLabel(p), AppColors.secondary),
                  if (p.isSeries) _chip('${p.episodeCount} episode${p.episodeCount == 1 ? '' : 's'}', AppColors.textSecondary),
                  if (p.orientation != null)
                    _chip(p.orientation == kOrientationLandscape ? '16:9' : '9:16', AppColors.textSecondary),
                  if (p.status != null) _chip(p.status == 'completed' ? 'Completed' : 'Ongoing', AppColors.textSecondary),
                  _chip(_watchSummary(p), p.publicEpisodeCount > 0 ? AppColors.success : AppColors.coin),
                ]),
              ]),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 8, 4),
          child: Wrap(spacing: 0, runSpacing: 0, crossAxisAlignment: WrapCrossAlignment.center, children: [
            TextButton.icon(onPressed: () => _open(p), icon: const Icon(Icons.open_in_new, size: 18), label: const Text('Open')),
            if (single != null) ...[
              _downloadButton(single),
              if (single.thumbnailUrl != null)
                IconButton(
                  tooltip: 'Download thumbnail',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _download(single, thumbnail: true),
                  icon: const Icon(Icons.image_outlined, size: 20, color: AppColors.primary),
                ),
            ] else ...[
              TextButton.icon(
                onPressed: downloadable == 0 ? null : () => _downloadAll(p),
                icon: const Icon(Icons.download, size: 18),
                label: Text('Download all ($downloadable)'),
              ),
              TextButton.icon(
                onPressed: () => setState(() => open ? _expanded.remove(p.id) : _expanded.add(p.id)),
                icon: Icon(open ? Icons.expand_less : Icons.expand_more, size: 18),
                label: Text(open ? 'Hide episodes' : 'Episodes'),
              ),
            ],
          ]),
        ),
        if (single != null) ...[_statusLine(single), _statusLine(single, thumbnail: true)],
        if (p.isSeries && open) ...[
          const Divider(height: 1, color: AppColors.surfaceBorder),
          if (p.episodes.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No episodes uploaded yet.', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
            ),
          for (final ep in p.episodes) _episodeRow(ep),
        ],
      ]),
    );
  }

  Widget _episodeRow(ProductionEpisode ep) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          SizedBox(
            width: 34,
            child: Text(ep.episodeNumber != null ? '${ep.episodeNumber}' : '–',
                style: const TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w700)),
          ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(ep.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14)),
              const SizedBox(height: 2),
              Text(_episodeMeta(ep), style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
            ]),
          ),
          IconButton(
            tooltip: 'Preview',
            onPressed: () => _preview(ep).catchError((_) => _snack("Couldn't open it right now.")),
            icon: const Icon(Icons.play_circle_outline, size: 22),
          ),
          if (ep.thumbnailUrl != null)
            IconButton(
              tooltip: 'Download thumbnail',
              onPressed: () => _download(ep, thumbnail: true),
              icon: const Icon(Icons.image_outlined, size: 20),
            ),
          _downloadIcon(ep),
        ]),
        _statusLine(ep, indent: 34),
        _statusLine(ep, indent: 34, thumbnail: true),
      ]),
    );
  }

  String _episodeMeta(ProductionEpisode ep) {
    final parts = <String>[
      switch (ep.watchStatus) { 'private' => 'Private', 'archived' => 'Archived', _ => 'On Viyo Watch' },
      if (ep.durationSeconds != null) _duration(ep.durationSeconds!),
      if (!ep.downloadable && ep.notDownloadableReason != null) ep.notDownloadableReason!,
    ];
    return parts.join(' · ');
  }

  String _duration(int s) => s >= 3600
      ? '${s ~/ 3600}h ${(s % 3600) ~/ 60}m'
      : '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';

  Widget _downloadButton(ProductionEpisode ep) {
    final st = _downloads[ep.postId];
    if (st?.running == true) {
      return TextButton.icon(
        onPressed: () => st.cancel?.cancel(),
        icon: const Icon(Icons.close, size: 18),
        label: Text(st!.progress == null ? 'Preparing…' : '${(st.progress! * 100).round()}% · Cancel'),
      );
    }
    return TextButton.icon(
      onPressed: ep.downloadable ? () => _download(ep) : null,
      icon: Icon(st?.error != null ? Icons.refresh : Icons.download, size: 18),
      label: Text(st?.error != null ? 'Retry' : (ep.downloadable ? 'Download MP4' : (ep.notDownloadableReason ?? 'Unavailable'))),
    );
  }

  Widget _downloadIcon(ProductionEpisode ep) {
    final st = _downloads[ep.postId];
    if (st?.running == true) {
      return SizedBox(
        width: 48,
        height: 48,
        child: InkWell(
          onTap: () => st.cancel?.cancel(),
          child: Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5, value: st!.progress),
            ),
          ),
        ),
      );
    }
    return IconButton(
      tooltip: st?.error != null ? 'Retry download' : 'Download MP4',
      onPressed: ep.downloadable ? () => _download(ep) : null,
      icon: Icon(st?.error != null ? Icons.refresh : (st?.done == true ? Icons.download_done : Icons.download), size: 22,
          color: st?.error != null ? AppColors.danger : (st?.done == true ? AppColors.success : null)),
    );
  }

  Widget _statusLine(ProductionEpisode ep, {double indent = 12, bool thumbnail = false}) {
    final st = _downloads[thumbnail ? '${ep.postId}:thumb' : ep.postId];
    if (st == null) return const SizedBox.shrink();
    String? text;
    Color color = AppColors.textMuted;
    if (st.error != null) {
      text = st.error;
      color = AppColors.danger;
    } else if (st.done) {
      text = saver.savesInBrowser ? 'Sent to your browser downloads' : 'Saved — share or save it from the menu';
      if (thumbnail) text = 'Thumbnail: $text';
      if (st.quality != null) text = '$text · ${st.quality}';
      color = AppColors.success;
    } else if (st.running && st.quality != null) {
      text = 'Downloading ${st.quality}';
    }
    if (text == null) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.fromLTRB(indent, 0, 12, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (st.running) ...[
          LinearProgressIndicator(value: st.progress, minHeight: 3, backgroundColor: Colors.white10),
          const SizedBox(height: 4),
        ],
        Text(text, style: TextStyle(color: color, fontSize: 12)),
      ]),
    );
  }

  Widget _thumb(String? url, {required bool vertical}) {
    final w = vertical ? 54.0 : 96.0;
    final h = vertical ? 96.0 : 54.0;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: w,
        height: h,
        color: AppColors.surfaceBorder,
        child: url == null
            ? const Icon(Icons.movie_outlined, color: AppColors.textMuted)
            : Image.network(url, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(Icons.movie_outlined, color: AppColors.textMuted)),
      ),
    );
  }

  Widget _chip(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
      );
}

class _RightsCard extends StatefulWidget {
  const _RightsCard();

  @override
  State<_RightsCard> createState() => _RightsCardState();
}

class _RightsCardState extends State<_RightsCard> {
  bool _open = false;

  static const _points = [
    ('Your work stays yours',
        'You own what you make, apart from anything that belongs to someone else (music, footage, voices, AI model terms).'),
    ('Post it anywhere', 'Download your videos and share them on YouTube, TikTok, Instagram, Facebook or your own site. Viyo is not exclusive.'),
    ('Viyo keeps its copy', "Downloading never removes your video from Viyo. What's on Viyo Watch stays there until you delete it."),
    ('Downloading is not publishing', 'Private videos stay private. Nothing goes on Viyo Watch unless you post it there.'),
    ('Check third-party rights', "If your video uses someone else's music, clips or voice, make sure their licence lets you post it elsewhere."),
    ('Removing content', 'Delete a post to remove it from Viyo Watch. Copies you downloaded or posted elsewhere are yours to manage.'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppTheme.card(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              const Icon(Icons.verified_user_outlined, color: AppColors.primary, size: 20),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('Your work, your rights — post it anywhere',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              ),
              Icon(_open ? Icons.expand_less : Icons.expand_more, color: AppColors.textMuted),
            ]),
          ),
        ),
        if (_open)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final (title, body) in _points) ...[
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 2),
                Text(body, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.35)),
                const SizedBox(height: 8),
              ],
            ]),
          ),
      ]),
    );
  }
}
