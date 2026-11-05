import 'dart:html' as html;

import 'package:dio/dio.dart';

typedef DownloadProgress = void Function(int received, int? total);

/// Browser download: hands the link to the browser, which streams the file
/// to the Downloads folder with its own progress and resume. Nothing is
/// loaded into the page's memory, so big films work too.
Future<String?> saveFromUrl({
  /// Returns a fresh (url, fileName). The file name must be the same on
  /// every call for the same item, so a retry resumes the same file.
  required Future<(String, String)> Function() freshUrl,
  DownloadProgress? onProgress,
  CancelToken? cancelToken,
}) async {
  final (url, fileName) = await freshUrl();
  html.AnchorElement(href: url)
    ..setAttribute('download', fileName)
    ..target = '_blank'
    ..rel = 'noopener'
    ..click();
  return null;
}

Future<void> shareSavedFile(String path, String mimeType) async {}

bool get savesInBrowser => true;
