/// Free web search for chat Deep Search when no Perplexity key is set.
///
/// Uses the same DuckDuckGo HTML parser as the agent `web_search` tool —
/// no API key, no account. Results are injected as context for the active
/// local/cloud model and surfaced as [WebSource] chips.
library;

import 'package:http/http.dart' as http;

import '../models/web_source.dart';
import '../services/tools/web_tools.dart';

class WebSearchHit {
  final String title;
  final String url;
  final String snippet;

  const WebSearchHit({
    required this.title,
    required this.url,
    this.snippet = '',
  });
}

class WebSearchResult {
  final List<WebSearchHit> hits;
  final List<WebSource> sources;
  final String? error;

  const WebSearchResult({
    this.hits = const [],
    this.sources = const [],
    this.error,
  });

  bool get ok => error == null && hits.isNotEmpty;

  /// Build context block appended to the user prompt for the model.
  String buildContextBlock() {
    if (hits.isEmpty) return '';
    final buf = StringBuffer()
      ..writeln('[Web search results]')
      ..writeln(
          'Use these snippets to ground the answer. Prefer citing source URLs.');
    for (var i = 0; i < hits.length; i++) {
      final h = hits[i];
      buf.writeln('${i + 1}. ${h.title}');
      buf.writeln('   URL: ${h.url}');
      if (h.snippet.isNotEmpty) buf.writeln('   ${h.snippet}');
    }
    buf.writeln('[End web search results]');
    return buf.toString();
  }

  String augmentPrompt(String prompt) {
    final block = buildContextBlock();
    if (block.isEmpty) return prompt;
    return '$prompt\n\n$block';
  }
}

class WebSearchService {
  WebSearchService._();

  /// DuckDuckGo HTML search — no key required.
  static Future<WebSearchResult> search(
    String query, {
    int maxResults = 5,
  }) async {
    final q = query.trim();
    if (q.isEmpty) {
      return const WebSearchResult(error: 'Empty query');
    }
    try {
      final uri = Uri.https('html.duckduckgo.com', '/html/', {'q': q});
      final resp = await http.get(uri, headers: {
        'User-Agent': 'CubicLM/1.0 (chat deep search)',
      }).timeout(const Duration(seconds: 12));
      if (resp.statusCode != 200) {
        return WebSearchResult(error: 'Search HTTP ${resp.statusCode}');
      }
      final raw = parseDuckResults(resp.body, maxResults.clamp(1, 8));
      if (raw.isEmpty) {
        return const WebSearchResult(error: 'No results');
      }
      final hits = raw
          .map((r) => WebSearchHit(
                title: r.title,
                url: r.url,
                snippet: r.snippet,
              ))
          .toList();
      final sources = hits
          .map((h) => WebSource(
                url: h.url,
                domain: WebSource.domainFromUrl(h.url),
                faviconUrl: WebSource.faviconFor(h.url),
                title: h.title,
                description: h.snippet,
              ))
          .toList();
      return WebSearchResult(hits: hits, sources: sources);
    } catch (e) {
      return WebSearchResult(error: 'Search failed: $e');
    }
  }
}
