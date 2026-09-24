import 'dart:typed_data';
import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';

/// Previews a freshly-picked image cross-platform. `Image.file` needs
/// a dart:io File, which doesn't work on web — this reads the picked
/// XFile's bytes instead (works identically everywhere image_picker
/// itself runs) and renders them with Image.memory.
class XFilePreviewImage extends StatelessWidget {
  final XFile file;
  final BoxFit fit;
  final double? width;
  final double? height;

  const XFilePreviewImage({
    super.key,
    required this.file,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: file.readAsBytes(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return SizedBox(
            width: width,
            height: height,
            child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        return Image.memory(snapshot.data!, fit: fit, width: width, height: height);
      },
    );
  }
}
