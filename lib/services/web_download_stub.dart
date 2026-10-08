/// Non-web stub — never actually called (callers only reach for this
/// behind `if (kIsWeb)`), but this file has to exist so the
/// conditional import resolves to *something* on mobile, where
/// dart:html itself doesn't compile at all.
void downloadBytesWeb(List<int> bytes, String fileName) {}
