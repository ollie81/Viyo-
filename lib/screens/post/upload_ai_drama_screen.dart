import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../models/post.dart';
import '../../models/series.dart';
import '../../services/post_service.dart';
import '../../services/series_service.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/guest_gate.dart';
import '../../widgets/upload_progress_card.dart';

/// Upload flow for AI Short Drama episodes — deliberately a separate
/// screen from CreatePostScreen rather than one more mode bolted onto
/// it: a drama upload always has a series + episode number and never
/// needs the caption-writing AI tools (hook check, voice check,
/// caption variants) that screen is built around, so sharing it would
/// mean threading a growing set of "only if this is a drama" branches
/// through logic that has nothing to do with series.
class UploadAiDramaScreen extends StatefulWidget {
  const UploadAiDramaScreen({super.key});

  @override
  State<UploadAiDramaScreen> createState() => _UploadAiDramaScreenState();
}

class _UploadAiDramaScreenState extends State<UploadAiDramaScreen> {
  File? _video;
  final _caption = TextEditingController();
  final _newSeriesTitle = TextEditingController();
  final _newSeriesDescription = TextEditingController();
  final _newSeriesPrice = TextEditingController(text: '20');

  List<Series> _mySeries = [];
  bool _loadingSeries = true;
  Series? _selectedSeries; // null while creating a brand-new series
  bool _creatingNewSeries = false;
  int _nextEpisodeNumber = 1;
  bool _loadingEpisodeNumber = false;

  bool _uploading = false;
  bool _posting = false;
  double _uploadProgress = 0;
  int _uploadTotalBytes = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSeries();
  }

  @override
  void dispose() {
    _caption.dispose();
    _newSeriesTitle.dispose();
    _newSeriesDescription.dispose();
    _newSeriesPrice.dispose();
    super.dispose();
  }

  Future<void> _loadSeries() async {
    final userId = SupabaseService.currentUserId;
    if (userId == null) {
      setState(() => _loadingSeries = false);
      return;
    }
    try {
      final series = await SeriesService.getUserSeries(userId);
      if (!mounted) return;
      setState(() {
        _mySeries = series;
        _creatingNewSeries = series.isEmpty;
        _loadingSeries = false;
      });
      if (series.isNotEmpty) _selectSeries(series.first);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingSeries = false;
        _creatingNewSeries = true;
      });
    }
  }

  Future<void> _selectSeries(Series series) async {
    setState(() {
      _selectedSeries = series;
      _creatingNewSeries = false;
      _loadingEpisodeNumber = true;
    });
    final next = await SeriesService.getNextEpisodeNumber(series.id);
    if (!mounted) return;
    setState(() {
      _nextEpisodeNumber = next;
      _loadingEpisodeNumber = false;
    });
  }

  void _startNewSeries() {
    setState(() {
      _selectedSeries = null;
      _creatingNewSeries = true;
      _nextEpisodeNumber = 1;
    });
  }

  Future<void> _pickVideo() async {
    final picked = await ImagePicker().pickVideo(source: ImageSource.gallery);
    if (picked != null) setState(() => _video = File(picked.path));
  }

  Future<void> _submit() async {
    final userId = SupabaseService.currentUserId;
    if (userId == null) return;
    if (_video == null) {
      setState(() => _error = 'Add a video first');
      return;
    }
    if (_creatingNewSeries && _newSeriesTitle.text.trim().isEmpty) {
      setState(() => _error = 'Give your new series a title');
      return;
    }
    if (!_creatingNewSeries && _selectedSeries == null) {
      setState(() => _error = 'Pick a series to add this episode to');
      return;
    }
    if (!await GuestGate.allow(context, action: 'upload an AI Short Drama')) return;

    setState(() {
      _posting = true;
      _error = null;
    });

    try {
      Series series;
      if (_creatingNewSeries) {
        final price = int.tryParse(_newSeriesPrice.text.trim()) ?? 20;
        series = await SeriesService.createSeries(
          userId: userId,
          title: _newSeriesTitle.text.trim(),
          description: _newSeriesDescription.text.trim(),
          coinPricePerEpisode: price.clamp(1, 100000),
        );
      } else {
        series = _selectedSeries!;
      }

      _uploadTotalBytes = await _video!.length();
      setState(() {
        _uploading = true;
        _uploadProgress = 0;
      });
      final mediaUrl = await PostService.uploadMediaWithProgress(
        _video!,
        userId,
        onProgress: (p) {
          if (mounted) setState(() => _uploadProgress = p);
        },
      );
      if (mounted) setState(() => _uploading = false);
      final thumbnailUrl = await PostService.generateAndUploadVideoThumbnail(_video!, userId);

      final episodeNumber = _creatingNewSeries ? 1 : _nextEpisodeNumber;
      await PostService.createPost(
        userId: userId,
        type: PostType.video,
        caption: _caption.text.trim(),
        mediaUrl: mediaUrl,
        thumbnailUrl: thumbnailUrl,
        seriesId: series.id,
        episodeNumber: episodeNumber,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Episode $episodeNumber of "${series.title}" is live 🎬')),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not upload episode: $e');
    } finally {
      if (mounted) setState(() { _posting = false; _uploading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _posting || _uploading;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.auto_awesome, size: 18, color: AppColors.secondary),
            SizedBox(width: 8),
            Text('Upload AI Short Drama'),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GestureDetector(
              onTap: busy ? null : _pickVideo,
              child: Container(
                height: 200,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.surfaceBorder),
                ),
                child: _video == null
                    ? const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.movie_creation_outlined, size: 36, color: AppColors.secondary),
                            SizedBox(height: 8),
                            Text('Choose your episode video', style: TextStyle(color: AppColors.textSecondary)),
                          ],
                        ),
                      )
                    : Stack(
                        children: [
                          const Center(
                            child: Icon(Icons.play_circle_outline, size: 48, color: AppColors.secondary),
                          ),
                          Positioned(
                            top: 8,
                            right: 8,
                            child: IconButton(
                              icon: const Icon(Icons.close, color: Colors.white),
                              onPressed: () => setState(() => _video = null),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 20),
            const Text('SERIES', style: TextStyle(fontSize: 11, letterSpacing: 0.8, color: AppColors.textMuted, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            if (_loadingSeries)
              const Center(child: CircularProgressIndicator(color: AppColors.secondary))
            else ...[
              if (_mySeries.isNotEmpty) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ..._mySeries.map((s) => _SeriesChip(
                          series: s,
                          selected: !_creatingNewSeries && _selectedSeries?.id == s.id,
                          onTap: busy ? null : () => _selectSeries(s),
                        )),
                    _NewSeriesChip(
                      selected: _creatingNewSeries,
                      onTap: busy ? null : _startNewSeries,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
              ],
              if (_creatingNewSeries) ...[
                TextField(
                  controller: _newSeriesTitle,
                  enabled: !busy,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(hintText: 'New series title'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _newSeriesDescription,
                  enabled: !busy,
                  maxLines: 2,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(hintText: 'What is this series about? (optional)'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _newSeriesPrice,
                  enabled: !busy,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    hintText: 'Coins to unlock one episode',
                    prefixIcon: Icon(Icons.monetization_on_outlined, color: AppColors.coin, size: 18),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'This episode will be Episode 1. The first $kFreeEpisodeCount episodes of every series are free to watch.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 11.5),
                ),
              ] else if (_selectedSeries != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: AppTheme.card(),
                  child: Row(
                    children: [
                      const Icon(Icons.movie_outlined, size: 16, color: AppColors.secondary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _loadingEpisodeNumber
                            ? const Text('Working out the next episode number...',
                                style: TextStyle(color: AppColors.textMuted, fontSize: 12.5))
                            : Text(
                                'This will be Episode $_nextEpisodeNumber of "${_selectedSeries!.title}"',
                                style: const TextStyle(fontSize: 12.5),
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _caption,
              enabled: !busy,
              maxLines: 3,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(hintText: 'Caption for this episode (optional)'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
            ],
            if (_uploading) ...[
              const SizedBox(height: 12),
              UploadProgressCard(uploading: true, progress: _uploadProgress, totalBytes: _uploadTotalBytes),
            ],
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: busy ? null : _submit,
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.secondary),
              child: busy
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Publish Episode'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SeriesChip extends StatelessWidget {
  final Series series;
  final bool selected;
  final VoidCallback? onTap;
  const _SeriesChip({required this.series, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? AppColors.secondary.withOpacity(0.18) : AppColors.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? AppColors.secondary : AppColors.surfaceBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(series.title, style: TextStyle(fontSize: 13, color: selected ? AppColors.secondary : AppColors.textSecondary, fontWeight: selected ? FontWeight.w700 : FontWeight.normal)),
            const SizedBox(width: 6),
            Text('${series.episodeCount} ep', style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted)),
          ],
        ),
      ),
    );
  }
}

class _NewSeriesChip extends StatelessWidget {
  final bool selected;
  final VoidCallback? onTap;
  const _NewSeriesChip({required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? AppColors.secondary.withOpacity(0.18) : AppColors.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? AppColors.secondary : AppColors.surfaceBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add, size: 14, color: selected ? AppColors.secondary : AppColors.textSecondary),
            const SizedBox(width: 4),
            Text('New series', style: TextStyle(fontSize: 13, color: selected ? AppColors.secondary : AppColors.textSecondary, fontWeight: selected ? FontWeight.w700 : FontWeight.normal)),
          ],
        ),
      ),
    );
  }
}
