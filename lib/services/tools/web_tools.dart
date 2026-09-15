/// CubicLM Agentic Tool System — built-in web tools.
///
/// Provides fetch_url (page → readable text) and web_search (DuckDuckGo,
/// no API key). Both are read-only and fail gracefully offline.
library;

import 'package:http/http.dart' as http;

import 'tool_interface.dart';

/// Fetch a URL and return readable text (HTML stripped, capped).
class FetchUrlTool extends Tool {
  @override
  String get name => 'fetch_url';

  @override
  String get description =>
      'Fetch a web page URL and return its readable text content. '
      'Use for: reading docs, checking APIs, grounding answers in real pages.';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'url': {
            'type': 'string',
            'description': 'The http(s) URL to fetch',
          },
          'max_chars': {
            'type': 'integer',
            'description':
                'Maximum characters to return. Default: 12000. Max: 30000.',
          },
        },
        'required': ['url'],
      };

  @override
  ToolRisk get risk => ToolRisk.safe;

  @override
  Future<ToolResult> execute(Map<String, dynamic> args, ToolContext context) async {
    final url = (args['url'] as String? ?? '').trim();
    if (url.isEmpty) return ToolResult.error('URL is required.');
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !(uri.scheme == 'http' || uri.scheme == 'https') ||
        uri.host.isEmpty) {
      return ToolResult.error('Only http(s) URLs are allowed.');
    }
    final maxChars = ((args['max_chars'] as num?) ?? 12000).toInt().clamp(1000, 30000);

    try {
      final resp = await http
          .get(uri, headers: {
            'User-Agent': 'CubicLM/1.0 (agentic workspace)',
            'Accept': 'text/html,text/plain,*/*',
          })
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        return ToolResult.error('HTTP ${resp.statusCode} for $url');
      }
      final contentType = resp.headers['content-type'] ?? '';
      final body = resp.body;
      final text = contentType.contains('html') || body.contains('<html')
          ? stripHtmlToText(body)
          : body.trim();
      if (text.isEmpty) return ToolResult.error('No readable text at $url');
      final out = 'Source: $url\n\n$text';
      if (out.length > maxChars) {
        return ToolResult.truncated(out.substring(0, maxChars));
      }
      return ToolResult(output: out);
    } catch (e) {
      return ToolResult.error('Fetch failed: $e');
    }
  }
}

/// Web search via DuckDuckGo HTML endpoint (no API key needed).
class WebSearchTool extends Tool {
  @override
  String get name => 'web_search';

  @override
  String get description =>
      'Search the web and return titles, URLs, and snippets. '
      'Use fetch_url afterwards to read a promising result in full.';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'query': {
            'type': 'string',
            'description': 'The search query',
          },
          'max_results': {
            'type': 'integer',
            'description':
                'Maximum results to return. Default: 5. Max: 10.',
          },
        },
        'required': ['query'],
      };

  @override
  ToolRisk get risk => ToolRisk.safe;

  @override
  Future<ToolResult> execute(Map<String, dynamic> args, ToolContext context) async {
    final query = (args['query'] as String? ?? '').trim();
    if (query.isEmpty) return ToolResult.error('Query is required.');
    final maxResults =
        ((args['max_results'] as num?) ?? 5).toInt().clamp(1, 10);

    try {
      final uri = Uri.https('html.duckduckgo.com', '/html/', {'q': query});
      final resp = await http
          .get(uri, headers: {
            'User-Agent': 'CubicLM/1.0 (agentic workspace)',
          })
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) {
        return ToolResult.error('Search HTTP ${resp.statusCode}');
      }
      final results = parseDuckResults(resp.body, maxResults);
      if (results.isEmpty) {
        return const ToolResult(output: 'No results found.');
      }
      final buf = StringBuffer();
      for (var i = 0; i < results.length; i++) {
        final r = results[i];
        buf.writeln('${i + 1}. ${r.title}');
        buf.writeln('   ${r.url}');
        if (r.snippet.isNotEmpty) buf.writeln('   ${r.snippet}');
        buf.writeln();
      }
      return ToolResult(output: buf.toString().trim());
    } catch (e) {
      return ToolResult.error('Search failed: $e');
    }
  }
}

/// One parsed search hit. Public for unit tests.
class WebHit {
  final String title;
  final String url;
  final String snippet;

  const WebHit({required this.title, required this.url, this.snippet = ''});
}

/// Parse DuckDuckGo HTML results. Public for unit tests.
List<WebHit> parseDuckResults(String html, int maxResults) {
  final out = <WebHit>[];
  // Result links: <a rel="nofollow" class="result__a" href="...">Title</a>
  final linkRe = RegExp(
    r'<a[^>]*class="result__a"[^>]*href="([^"]+)"[^>]*>(.*?)</a>',
    dotAll: true,
  );
  final snipRe = RegExp(
    r'<a[^>]*class="result__snippet"[^>]*>(.*?)</a>',
    dotAll: true,
  );
  final links = linkRe.allMatches(html).toList();
  final snips = snipRe.allMatches(html).toList();
  for (var i = 0; i < links.length && out.length < maxResults; i++) {
    var href = links[i].group(1)!.trim();
    // DuckDuckGo wraps in //duckduckgo.com/l/?uddg=<encoded>
    final uddg = RegExp(r'[?&]uddg=([^&]+)').firstMatch(href);
    if (uddg != null) {
      try {
        href = Uri.decodeComponent(uddg.group(1)!);
      } catch (_) {}
    }
    final title = stripHtmlToText(links[i].group(2) ?? '').trim();
    final snippet =
        i < snips.length ? stripHtmlToText(snips[i].group(1) ?? '').trim() : '';
    if (href.isEmpty) continue;
    out.add(WebHit(title: title.isEmpty ? href : title, url: href, snippet: snippet));
  }
  return out;
}

/// Strip HTML down to readable text. Public for unit tests.
String stripHtmlToText(String html) {
  var s = html;
  s = s.replaceAll(RegExp(r'<(script|style|noscript)[^>]*>.*?</\1>',
      dotAll: true, caseSensitive: false), ' ');
  s = s.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), ' ');
  s = s.replaceAll(RegExp(r'<[^>]+>'), ' ');
  s = s
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'");
  s = s.replaceAll(RegExp(r'[ \t\x0B\f\r]+'), ' ');
  s = s.replaceAll(RegExp(r' *\n *'), '\n');
  s = s.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return s.trim();
}

/// Get all built-in web tools.
List<Tool> webTools() => [
      FetchUrlTool(),
      WebSearchTool(),
    ];
