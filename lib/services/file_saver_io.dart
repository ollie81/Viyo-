import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

typedef DownloadProgress = void Function(int received, int? total);

/// Phone (Android) download: streams the file to the app's own storage —
/// never into memory — and resumes a partial file on retry (HTTP Range),
/// asking for a fresh link each attempt since links expire.
/// Returns the saved file's path.
Future<String?> saveFromUrl({
  /// Returns a fresh (url, fileName). The file name must be the same on
  /// every call for the same item, so a retry resumes the same file.
  required Future<(String, String)> Function() freshUrl,
  DownloadProgress? onProgress,
  CancelToken? cancelToken,
}) async {
  final (url, fileName) = await freshUrl();
  final dir = Directory('${(await getTemporaryDirectory()).path}/viyo_downloads');
  await dir.create(recursive: true);
  final finalFile = File('${dir.path}/${fileName.replaceAll(RegExp(r'[/\\]'), '_')}');
  return downloadResumable(url: url, target: finalFile, onProgress: onProgress, cancelToken: cancelToken);
}

/// Streams [url] into [target], keeping a `.part` file until the last byte
/// arrives. Calling it again after a failure continues from where the part
/// file stopped (HTTP Range); if the server ignores Range it starts over.
@visibleForTesting
Future<String> downloadResumable({
  required String url,
  required File target,
  DownloadProgress? onProgress,
  CancelToken? cancelToken,
  Dio? dio,
}) async {
  final finalFile = target;
  final part = File('${finalFile.path}.part');
  final have = await part.exists() ? await part.length() : 0;

  final res = await (dio ?? Dio()).get<ResponseBody>(
    url,
    cancelToken: cancelToken,
    options: Options(
      responseType: ResponseType.stream,
      headers: {if (have > 0) 'Range': 'bytes=$have-'},
      validateStatus: (s) => s != null && (s == 200 || s == 206 || s == 416),
    ),
  );
  final status = res.statusCode ?? 0;
  if (status == 416) {
    // Already have every byte from an earlier attempt.
    await part.rename(finalFile.path);
    return finalFile.path;
  }
  final resuming = status == 206 && have > 0;
  final lengthHeader = int.tryParse(res.headers.value(Headers.contentLengthHeader) ?? '');
  final total = lengthHeader == null ? null : lengthHeader + (resuming ? have : 0);
  var received = resuming ? have : 0;
  final sink = part.openWrite(mode: resuming ? FileMode.append : FileMode.write);
  try {
    await for (final chunk in res.data!.stream) {
      sink.add(chunk);
      received += chunk.length;
      onProgress?.call(received, total);
    }
    await sink.flush();
  } finally {
    await sink.close();
  }
  if (total != null && received < total) {
    throw const FileSystemException('The download stopped early. Tap retry to continue.');
  }
  if (await finalFile.exists()) await finalFile.delete();
  await part.rename(finalFile.path);
  return finalFile.path;
}


/// Opens the phone's share sheet so the creator can save the file to their
/// gallery/Files or send it straight to TikTok, YouTube, Instagram...
Future<void> shareSavedFile(String path, String mimeType) async {
  await Share.shareXFiles([XFile(path, mimeType: mimeType)]);
}

bool get savesInBrowser => false;
