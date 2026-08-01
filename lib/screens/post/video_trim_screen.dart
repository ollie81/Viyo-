import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_trimmer/video_trimmer.dart';
import '../../theme/app_theme.dart';

/// Lets the user trim a picked video down to the best 30s (or less)
/// before it's uploaded. Returns the trimmed file's path via Navigator.pop.
class VideoTrimScreen extends StatefulWidget {
  final File file;
  const VideoTrimScreen({super.key, required this.file});

  @override
  State<VideoTrimScreen> createState() => _VideoTrimScreenState();
}

class _VideoTrimScreenState extends State<VideoTrimScreen> {
  final _trimmer = Trimmer();
  double _start = 0;
  double _end = 0;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await _trimmer.loadVideo(videoFile: widget.file);
    setState(() {});
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    String? outputPath;
    await _trimmer.saveTrimmedVideo(
      startValue: _start,
      endValue: _end,
      onSave: (path) => outputPath = path,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.of(context).pop(outputPath);
  }

  @override
  void dispose() {
    _trimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Trim video'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Done', style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: VideoViewer(trimmer: _trimmer),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: TrimViewer(
              trimmer: _trimmer,
              viewerHeight: 50,
              viewerWidth: MediaQuery.of(context).size.width - 32,
              maxVideoLength: const Duration(seconds: 30),
              onChangeStart: (v) => _start = v,
              onChangeEnd: (v) => _end = v,
              onChangePlaybackState: (_) {},
            ),
          ),
        ],
      ),
    );
  }
}
