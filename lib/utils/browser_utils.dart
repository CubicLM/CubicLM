/// Pure-Dart helpers for the CubicWeb Browser.
///
/// No Flutter / GetX / platform dependencies — safe to unit test on the VM.
library;

/// Search engine descriptor: stable [id], display [name], URL [template]
/// where `%s` is replaced with the URL-encoded query.
class BrowserEngine {
  final String id;
  final String name;
  final String template;

  const BrowserEngine({
    required this.id,
    required this.name,
    required this.template,
  });
}

/// Supported search engines. DuckDuckGo stays the default (privacy-first,
/// matches previous behavior).
class BrowserSearchEngines {
  BrowserSearchEngines._();

  static const List<BrowserEngine> engines = [
    BrowserEngine(
        id: 'duckduckgo',
        name: 'DuckDuckGo',
        template: 'https://duckduckgo.com/?q=%s'),
    BrowserEngine(
        id: 'brave', name: 'Brave', template: 'https://search.brave.com/search?q=%s'),
    BrowserEngine(
        id: 'google',
        name: 'Google',
        template: 'https://www.google.com/search?q=%s'),
    BrowserEngine(
        id: 'bing', name: 'Bing', template: 'https://www.bing.com/search?q=%s'),
    BrowserEngine(
        id: 'startpage',
        name: 'Startpage',
        template: 'https://www.startpage.com/sp/search?query=%s'),
  ];

  static const String defaultId = 'duckduckgo';

  /// Search URL for [query] using engine [engineId].
  /// Unknown ids fall back to DuckDuckGo.
  static String searchUrl(String engineId, String query) {
    final engine = engines.firstWhere(
      (e) => e.id == engineId,
      orElse: () => engines.first,
    );
    return engine.template.replaceFirst('%s', Uri.encodeQueryComponent(query));
  }

  static bool isKnown(String engineId) =>
      engines.any((e) => e.id == engineId);
}

/// URL-bar indicator kind, derived from the current URL's scheme.
enum BrowserUrlKind { blank, https, http, other }

/// Classify [url] for the URL-bar security indicator.
BrowserUrlKind classifyUrl(String url) {
  final u = url.trim().toLowerCase();
  if (u.isEmpty || u == 'about:blank') return BrowserUrlKind.blank;
  if (u.startsWith('https://')) return BrowserUrlKind.https;
  if (u.startsWith('http://')) return BrowserUrlKind.http;
  return BrowserUrlKind.other;
}

/// True when navigating from [current] to [next] should push [current]
/// onto the back stack. Guards against blank pages, same-URL repeats
/// (redirect/SPA double-fire between onLoadStart and
/// onUpdateVisitedHistory) and consecutive duplicates.
bool shouldPushHistory({
  required String? current,
  required String next,
  String? lastInStack,
}) {
  final c = (current ?? '').trim();
  final n = next.trim();
  if (n.isEmpty || n == 'about:blank') return false;
  if (c.isEmpty || c == 'about:blank') return false;
  if (n == c) return false;
  if (lastInStack != null && lastInStack.trim() == c) return false;
  return true;
}

/// Best-effort download filename. Prefers the server-suggested name, then
/// RFC 6266/5987 `Content-Disposition`, then the URL path segment.
/// Always returns a filesystem-safe, non-empty name.
String downloadFilename({
  String? suggested,
  String? contentDisposition,
  required String url,
}) {
  String clean(String s) {
    var name = s.split('/').last.split('\\').last.trim();
    name = name.replaceAll(RegExp(r'[<>:"|?*\x00-\x1F]'), '_');
    return name;
  }

  final s = (suggested ?? '').trim();
  if (s.isNotEmpty) {
    final c = clean(s);
    if (c.isNotEmpty) return c;
  }
  final cd = (contentDisposition ?? '').trim();
  if (cd.isNotEmpty) {
    // RFC 5987: filename*=UTF-8''example.pdf
    final star = RegExp("filename\\*\\s*=\\s*[^']*'[^']*'([^;]+)",
            caseSensitive: false)
        .firstMatch(cd);
    if (star != null) {
      try {
        final decoded = Uri.decodeComponent(star.group(1)!.trim());
        final c = clean(decoded);
        if (c.isNotEmpty) return c;
      } catch (_) {}
    }
    final quoted =
        RegExp('filename\\s*=\\s*"([^"]+)"', caseSensitive: false)
            .firstMatch(cd);
    if (quoted != null) {
      final c = clean(quoted.group(1)!);
      if (c.isNotEmpty) return c;
    }
    final bare =
        RegExp('filename\\s*=\\s*([^;\\s]+)', caseSensitive: false)
            .firstMatch(cd);
    if (bare != null) {
      final c = clean(bare.group(1)!);
      if (c.isNotEmpty) return c;
    }
  }
  try {
    final seg = Uri.parse(url.trim()).pathSegments;
    final last = seg.isEmpty ? '' : clean(seg.last);
    if (last.isNotEmpty) return last;
  } catch (_) {}
  return 'download';
}

/// Desktop-mode user agent (Chromium on Windows 10).
const String kDesktopUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
    'AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/126.0.0.0 Safari/537.36';

/// Standalone reader-mode document. A `<base>` tag resolves relative
/// image/link URLs against the source page; [fontSize] scales body text.
String readerDocument({
  required String pageUrl,
  required String bodyHtml,
  required double fontSize,
  required bool isDark,
}) {
  final fg = isDark ? '#eee' : '#111';
  final bg = isDark ? '#262624' : '#F8F4ED';
  return '''
<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<base href="$pageUrl">
<style>
body {
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
  line-height: 1.6;
  font-size: ${fontSize.toStringAsFixed(0)}px;
  color: $fg;
  background: $bg;
  padding: 20px;
  max-width: 800px;
  margin: 0 auto;
}
img { max-width: 100%; height: auto; border-radius: 8px; margin: 10px 0; }
h1, h2, h3 { line-height: 1.2; }
a { color: #4f8ff7; }
pre, code { white-space: pre-wrap; word-break: break-word; }
</style>
</head>
<body>$bodyHtml</body>
</html>
''';
}

/// Ranked session top-sites from per-host visit [counts].
/// Pure (input map is not mutated) — safe to unit test.
List<MapEntry<String, int>> topSites(Map<String, int> counts, int limit) {
  final entries = counts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return entries.take(limit).toList();
}
