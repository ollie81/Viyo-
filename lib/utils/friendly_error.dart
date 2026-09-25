/// Turns a caught error into something a person can actually act on,
/// instead of the raw exception — "ClientException: Failed to fetch,
/// uri=https://viyoai-production.up.railway.app/..." explains what
/// happened to the browser's fetch() call, not to whoever is holding
/// the phone. A dropped/too-weak connection is by far the most common
/// cause of that particular failure shape, so it gets a message that
/// actually points at the fix (check your signal) instead of a URL.
String friendlyErrorMessage(Object error) {
  final text = error.toString();
  final looksLikeConnectivityFailure = text.contains('Failed to fetch') ||
      text.contains('SocketException') ||
      text.contains('Connection failed') ||
      text.contains('Connection refused') ||
      text.contains('Network is unreachable') ||
      text.contains('Failed host lookup') ||
      text.contains('TimeoutException') ||
      text.contains('Connection timed out');
  if (looksLikeConnectivityFailure) {
    return "Couldn't connect — check your signal and try again.";
  }
  // Not a connectivity failure — still strip the exception-class noise
  // ("Exception: "/"ClientException: ") so what's left reads as a
  // sentence instead of a stack-trace fragment.
  return text.replaceFirst(RegExp(r'^(Client)?Exception:\s*'), '');
}
