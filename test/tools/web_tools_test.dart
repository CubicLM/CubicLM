import 'package:flutter_test/flutter_test.dart';

import 'package:cubiclm/services/tools/tool_interface.dart';
import 'package:cubiclm/services/tools/web_tools.dart';

void main() {
  group('stripHtmlToText', () {
    test('removes scripts, styles, comments, and tags', () {
      const html = '''
<html><head><style>.x{color:red}</style>
<script>alert(1)</script></head>
<body><!-- hidden --><h1>Title</h1><p>Hello &amp; bye</p></body></html>
''';
      final text = stripHtmlToText(html);
      expect(text, contains('Title'));
      expect(text, contains('Hello & bye'));
      expect(text, isNot(contains('alert')));
      expect(text, isNot(contains('<')));
    });

    test('collapses blank lines', () {
      expect(stripHtmlToText('<p>a</p><p>b</p>'), isNot(contains('\n\n\n')));
    });
  });

  group('parseDuckResults', () {
    test('extracts titles, urls, and snippets', () {
      const html = '''
<a rel="nofollow" class="result__a" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fexample.com%2Fpage&amp;rut=x">Example Page</a>
<a class="result__snippet" href="x">A fine snippet</a>
''';
      final hits = parseDuckResults(html, 5);
      expect(hits.length, 1);
      expect(hits.first.title, 'Example Page');
      expect(hits.first.url, 'https://example.com/page');
      expect(hits.first.snippet, 'A fine snippet');
    });

    test('empty html yields no hits', () {
      expect(parseDuckResults('<html></html>', 5), isEmpty);
    });
  });

  group('web tool schemas', () {
    test('both tools expose OpenAI schemas', () {
      for (final tool in webTools()) {
        final schema = toolToOpenAI(tool);
        expect((schema['function'] as Map)['name'], tool.name);
      }
      expect(webTools().map((t) => t.name),
          containsAll(['fetch_url', 'web_search']));
    });

    test('fetch_url rejects non-http urls without network', () async {
      final result = await FetchUrlTool().execute(
        {'url': 'ftp://example.com/x'},
        ToolContext(workspacePath: '', approve: (_, __) async => true),
      );
      expect(result.success, isFalse);
    });
  });
}
