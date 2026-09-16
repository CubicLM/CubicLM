/// CubicLM Preview Guard — loopback-only navigation for WebViews.
///
/// Agent-generated web content renders in embedded WebViews. To stop a
/// malicious or compromised preview from exfiltrating data, in-preview
/// navigation is restricted to loopback origins plus inert schemes
/// (`data:`, `about:`, `blob:`) — Mobile-Harness parity
/// (`PocketDevApp` preview URL restriction). Anything else is routed to
/// the system browser via the caller's external handler.
///
/// Pure Dart — fully unit-testable.
library;

/// True when a preview WebView may navigate to [url] inline.
bool isPreviewUrlAllowed(String url) {
  final u = Uri.tryParse(url.trim());
  if (u == null || !u.hasScheme) return false;
  final scheme = u.scheme.toLowerCase();
  // Inert content: inline payloads and blank pages.
  if (scheme == 'data' || scheme == 'about' || scheme == 'blob') return true;
  if (scheme != 'http' && scheme != 'https') return false;
  final host = u.host.toLowerCase();
  if (host.isEmpty) return false;
  if (host == 'localhost' ||
      host == '127.0.0.1' ||
      host == '::1' ||
      host == '[::1]') {
    return true;
  }
  // `*.localhost` resolves to loopback per RFC 6761 §6.3.
  if (host == 'localhost' || host.endsWith('.localhost')) return true;
  return false;
}

final _loopbackUrlRe = RegExp(
  r'https?://(?:localhost|127\.0\.0\.1|[a-zA-Z0-9-]+\.localhost)(?::\d+)?(?:/[^\s)\]"<>]*)?',
);

/// First loopback URL in free text (terminal output, logs), or null.
/// Mobile-Harness parity: dev servers print `http://localhost:3000` —
/// the terminal surfaces it as an openable preview chip. Only matches
/// [isPreviewUrlAllowed] origins. Pure for unit tests.
String? findPreviewUrl(String text) {
  try {
    final m = _loopbackUrlRe.firstMatch(text);
    if (m == null) return null;
    final url = m.group(0)!;
    return isPreviewUrlAllowed(url) ? url : null;
  } catch (_) {
    return null;
  }
}
