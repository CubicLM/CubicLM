import 'package:flutter_test/flutter_test.dart';
import 'package:cubiclm/models/web_source.dart';
import 'package:cubiclm/services/tools/web_tools.dart';
import 'package:cubiclm/services/web_search_service.dart';

void main() {
  group('parseDuckResults', () {
    test('parses titles, urls, snippets and unwraps uddg links', () {
      const html = '''
      <div class="result">
        <a rel="nofollow" class="result__a" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fexample.com%2Fpage">Example <b>Page</b></a>
        <a class="result__snippet">A short snippet about example.</a>
      </div>
      <div class="result">
        <a rel="nofollow" class="result__a" href="https://flutter.dev">Flutter</a>
        <a class="result__snippet">UI toolkit</a>
      </div>
      ''';
      final hits = parseDuckResults(html, 5);
      expect(hits.length, 2);
      expect(hits[0].url, 'https://example.com/page');
      expect(hits[0].title, 'Example Page');
      expect(hits[0].snippet, 'A short snippet about example.');
      expect(hits[1].url, 'https://flutter.dev');
    });

    test('respects maxResults', () {
      final buf = StringBuffer();
      for (var i = 0; i < 8; i++) {
        buf.writeln(
            '<a class="result__a" href="https://e$i.com">T$i</a><a class="result__snippet">S$i</a>');
      }
      expect(parseDuckResults(buf.toString(), 3).length, 3);
    });

    test('stripHtmlToText removes tags and entities', () {
      expect(stripHtmlToText('<p>Hello&nbsp;<b>world</b></p>'),
          'Hello world');
    });
  });

  group('WebSearchResult prompt augmentation', () {
    test('augmentPrompt injects URLs and ends cleanly', () {
      final r = WebSearchResult(hits: const [
        WebSearchHit(
            title: 'Docs', url: 'https://docs.example', snippet: 'API docs'),
      ], sources: [
        WebSource(
          url: 'https://docs.example',
          domain: 'docs.example',
          faviconUrl: WebSource.faviconFor('https://docs.example'),
          title: 'Docs',
        ),
      ]);
      expect(r.ok, isTrue);
      final out = r.augmentPrompt('What is CubicLM?');
      expect(out, startsWith('What is CubicLM?'));
      expect(out, contains('[Web search results]'));
      expect(out, contains('https://docs.example'));
      expect(out, contains('[End web search results]'));
      expect(r.sources.single.domain, 'docs.example');
    });

    test('empty result does not change prompt', () {
      const r = WebSearchResult(error: 'No results');
      expect(r.ok, isFalse);
      expect(r.augmentPrompt('hello'), 'hello');
    });
  });
}
