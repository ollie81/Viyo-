import 'dart:typed_data';

/// Non-web stub — never actually called (post_service.dart and
/// series_service.dart only reach for these behind `if (kIsWeb)`), but
/// this file has to exist so the conditional import resolves to
/// *something* on mobile, where dart:html itself doesn't compile at all.
Future<Uint8List?> captureVideoFrameWeb(Uint8List videoBytes) async => null;

Future<Uint8List?> captureVideoFrameFromUrlWeb(String url) async => null;
