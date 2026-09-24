import 'dart:typed_data';

/// Non-web stub — never actually called (post_service.dart only reaches
/// for this behind `if (kIsWeb)`), but this file has to exist so the
/// conditional import in post_service.dart resolves to *something* on
/// mobile, where dart:html itself doesn't compile at all.
Future<Uint8List?> captureVideoFrameWeb(Uint8List videoBytes) async => null;
