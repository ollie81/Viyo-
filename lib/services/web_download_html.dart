import 'dart:html' as html;

/// Triggers a real browser download — the web substitute for the
/// native path's getTemporaryDirectory()+File()+share_plus flow, none
/// of which exist on web (dart:io has no filesystem there, which is
/// exactly what MissingPluginException(getTemporaryDirectory) was:
/// that native-only code path being reached on a web build at all).
/// A Blob URL + a programmatically-clicked, invisible <a download>
/// is the standard way a browser tab saves bytes to the user's
/// Downloads folder without any plugin.
void downloadBytesWeb(List<int> bytes, String fileName) {
  final blob = html.Blob([bytes]);
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', fileName)
    ..click();
  html.Url.revokeObjectUrl(url);
}
