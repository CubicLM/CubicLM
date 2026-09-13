import 'package:flutter_test/flutter_test.dart';

import 'package:cubiclm/utils/browser_utils.dart';

/// CubicWeb Browser helpers: pure-Dart logic, no platform channels.
void main() {
  group('BrowserSearchEngines.searchUrl', () {
    test('default engine is DuckDuckGo', () {
      expect(BrowserSearchEngines.defaultId, 'duckduckgo');
      expect(
          BrowserSearchEngines.searchUrl('duckduckgo', 'weather dhaka'),
          'https://duckduckgo.com/?q=weather+dhaka');
    });

    test('each engine builds its own URL', () {
      expect(BrowserSearchEngines.searchUrl('google', 'flutter'),
          'https://www.google.com/search?q=flutter');
      expect(BrowserSearchEngines.searchUrl('brave', 'flutter'),
          'https://search.brave.com/search?q=flutter');
      expect(BrowserSearchEngines.searchUrl('bing', 'flutter'),
          'https://www.bing.com/search?q=flutter');
      expect(BrowserSearchEngines.searchUrl('startpage', 'flutter'),
          'https://www.startpage.com/sp/search?query=flutter');
    });

    test('unknown engine falls back to DuckDuckGo', () {
      expect(BrowserSearchEngines.searchUrl('nope', 'x'),
          'https://duckduckgo.com/?q=x');
      expect(BrowserSearchEngines.isKnown('nope'), isFalse);
      expect(BrowserSearchEngines.isKnown('google'), isTrue);
    });

    test('query is URL-encoded', () {
      expect(BrowserSearchEngines.searchUrl('duckduckgo', 'a&b=c?d'),
          contains('a%26b%3Dc%3Fd'));
    });
  });

  group('classifyUrl', () {
    test('blank pages', () {
      expect(classifyUrl(''), BrowserUrlKind.blank);
      expect(classifyUrl('about:blank'), BrowserUrlKind.blank);
    });

    test('schemes', () {
      expect(classifyUrl('https://example.com'),
          BrowserUrlKind.https);
      expect(
          classifyUrl('HTTPS://EXAMPLE.COM'), BrowserUrlKind.https);
      expect(
          classifyUrl('http://example.com'), BrowserUrlKind.http);
      expect(classifyUrl('file:///x.html'), BrowserUrlKind.other);
    });
  });

  group('shouldPushHistory', () {
    test('pushes normal navigations', () {
      expect(
          shouldPushHistory(current: 'https://a.com/', next: 'https://b.com/'),
          isTrue);
    });

    test('rejects blanks, repeats and consecutive duplicates', () {
      expect(shouldPushHistory(current: '', next: 'https://b.com/'),
          isFalse);
      expect(shouldPushHistory(current: 'about:blank', next: 'https://b.com/'),
          isFalse);
      expect(
          shouldPushHistory(
              current: 'https://a.com/', next: 'about:blank'),
          isFalse);
      expect(
          shouldPushHistory(
              current: 'https://a.com/', next: 'https://a.com/'),
          isFalse);
      expect(
          shouldPushHistory(
              current: 'https://a.com/',
              next: 'https://b.com/',
              lastInStack: 'https://a.com/'),
          isFalse);
    });
  });

  group('downloadFilename', () {
    test('prefers the suggested filename', () {
      expect(
          downloadFilename(
              suggested: 'report.pdf', url: 'https://x.com/dl?id=1'),
          'report.pdf');
    });

    test('parses Content-Disposition', () {
      expect(
          downloadFilename(
              contentDisposition: 'attachment; filename="a b.zip"',
              url: 'https://x.com/dl'),
          'a b.zip');
      expect(
          downloadFilename(
              contentDisposition: 'attachment; filename=plain.apk',
              url: 'https://x.com/dl'),
          'plain.apk');
      expect(
          downloadFilename(
              contentDisposition:
                  "attachment; filename*=UTF-8''%E0%A6%95%E0%A6%AC%E0%A6%BF.pdf",
              url: 'https://x.com/dl'),
          isNotEmpty);
    });

    test('falls back to the URL path, then a default', () {
      expect(downloadFilename(url: 'https://x.com/files/app.apk'),
          'app.apk');
      expect(downloadFilename(url: 'https://x.com/dl?id=1'), 'dl');
      expect(downloadFilename(url: 'https://x.com/'), 'download');
      expect(downloadFilename(url: '::::'), 'download');
    });

    test('sanitizes unsafe characters', () {
      final name = downloadFilename(
          suggested: 'a<b>:"c".txt', url: 'https://x.com/');
      expect(name.contains(RegExp(r'[<>:"|?*]')), isFalse);
    });
  });

  group('readerDocument', () {
    test('resolves relative URLs and applies theme + font size', () {
      final doc = readerDocument(
          pageUrl: 'https://example.com/a/b',
          bodyHtml: '<p>hi</p>',
          fontSize: 20,
          isDark: true);
      expect(doc, contains('<base href="https://example.com/a/b">'));
      expect(doc, contains('font-size: 20px'));
      expect(doc, contains('#262624'));
      expect(doc, contains('<p>hi</p>'));
    });

    test('light theme uses the warm canvas', () {
      final doc = readerDocument(
          pageUrl: 'https://example.com/',
          bodyHtml: '',
          fontSize: 18,
          isDark: false);
      expect(doc, contains('#F8F4ED'));
    });
  });

  group('topSites', () {
    test('ranks by count and respects the limit', () {
      final ranked = topSites({'b.com': 1, 'a.com': 5, 'c.com': 3}, 2);
      expect(ranked.map((e) => e.key), ['a.com', 'c.com']);
    });

    test('does not mutate the input', () {
      final counts = {'a.com': 2};
      topSites(counts, 5);
      expect(counts, {'a.com': 2});
    });
  });
}
