import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

/// Extracts one JPEG frame from a video's raw bytes using the browser's
/// own <video>/<canvas> element APIs — the video_thumbnail plugin
/// (post_service.dart's native path) has no web implementation at all,
/// so this is the web substitute. Only ever loaded on web builds: the
/// conditional import in post_service.dart picks this file over
/// web_thumbnail_stub.dart specifically when dart:library.html exists.
Future<Uint8List?> captureVideoFrameWeb(Uint8List videoBytes) async {
  final blob = html.Blob([videoBytes]);
  final objectUrl = html.Url.createObjectUrlFromBlob(blob);
  final video = html.VideoElement()
    ..src = objectUrl
    ..muted = true
    ..preload = 'auto';

  try {
    return await _captureFrame(video);
  } finally {
    html.Url.revokeObjectUrl(objectUrl);
  }
}

/// Same capture, but reading a video that's already hosted somewhere
/// (Supabase Storage) rather than freshly picked bytes — used to
/// backfill a thumbnail for a video that was uploaded before this file
/// existed (see SeriesService's cover-image backfill), without
/// re-downloading and re-uploading the whole clip. Needs the resource
/// to actually serve permissive CORS (confirmed for this app's public
/// storage bucket) — canvas.toBlob throws a SecurityError on a tainted
/// (cross-origin, no CORS) canvas otherwise, which surfaces here as a
/// null return like any other capture failure.
Future<Uint8List?> captureVideoFrameFromUrlWeb(String url) async {
  final video = html.VideoElement()
    ..crossOrigin = 'anonymous'
    ..src = url
    ..muted = true
    ..preload = 'auto';

  return _captureFrame(video);
}

Future<Uint8List?> _captureFrame(html.VideoElement video) async {
  try {
    await video.onLoadedMetadata.first.timeout(const Duration(seconds: 15));

    // A touch into the clip, same as the native path's timeMs: 500 —
    // skips a possible black opening frame. Falls back to the very
    // first frame for a clip shorter than that.
    final duration = video.duration;
    video.currentTime = (duration.isFinite && duration > 0.5) ? 0.5 : 0.0;
    await video.onSeeked.first.timeout(const Duration(seconds: 15));

    final width = video.videoWidth;
    final height = video.videoHeight;
    if (width == 0 || height == 0) return null;

    final canvas = html.CanvasElement(width: width, height: height);
    canvas.context2D.drawImage(video, 0, 0);

    final jpegBlob = await canvas.toBlob('image/jpeg', 0.75);

    final reader = html.FileReader();
    final completer = Completer<Uint8List?>();
    reader.onLoadEnd.first.then((_) {
      final buffer = reader.result;
      completer.complete(buffer is ByteBuffer ? buffer.asUint8List() : null);
    });
    reader.onError.first.then((_) => completer.complete(null));
    reader.readAsArrayBuffer(jpegBlob);

    return await completer.future.timeout(const Duration(seconds: 15));
  } catch (_) {
    return null;
  }
}
