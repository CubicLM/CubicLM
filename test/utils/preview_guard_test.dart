import 'package:flutter_test/flutter_test.dart';

import 'package:cubiclm/utils/preview_guard.dart';

void main() {
  group('isPreviewUrlAllowed', () {
    test('allows loopback http(s)', () {
      expect(isPreviewUrlAllowed('http://localhost:3000/'), isTrue);
      expect(isPreviewUrlAllowed('https://localhost/'), isTrue);
      expect(isPreviewUrlAllowed('http://127.0.0.1:8080/x'), isTrue);
      expect(isPreviewUrlAllowed('http://app.localhost:3000/'), isTrue);
    });

    test('allows inert schemes', () {
      expect(isPreviewUrlAllowed('about:blank'), isTrue);
      expect(isPreviewUrlAllowed('data:text/html,<h1>hi</h1>'), isTrue);
      expect(isPreviewUrlAllowed('blob:https://localhost/uuid'), isTrue);
    });

    test('blocks external and dangerous schemes', () {
      expect(isPreviewUrlAllowed('https://example.com/'), isFalse);
      expect(isPreviewUrlAllowed('http://evil-localhost.com/'), isFalse);
      expect(isPreviewUrlAllowed('http://localhost.evil.com/'), isFalse);
      expect(isPreviewUrlAllowed('javascript:alert(1)'), isFalse);
      expect(isPreviewUrlAllowed('file:///etc/passwd'), isFalse);
      expect(isPreviewUrlAllowed(''), isFalse);
      expect(isPreviewUrlAllowed('not a url \\'), isFalse);
    });
  });

  group('findPreviewUrl', () {
    test('extracts loopback URLs from terminal output', () {
      expect(
        findPreviewUrl('Server running at http://localhost:3000/ ready'),
        'http://localhost:3000/',
      );
      expect(
        findPreviewUrl('vite v5.0.0 ready in 300 ms\n➜  Local: http://127.0.0.1:5173/app'),
        'http://127.0.0.1:5173/app',
      );
      expect(
        findPreviewUrl('listening on https://api.localhost:8443/v1)'),
        'https://api.localhost:8443/v1',
      );
    });

    test('ignores external URLs and plain text', () {
      expect(findPreviewUrl('see https://example.com/docs'), isNull);
      expect(findPreviewUrl('no urls here'), isNull);
      expect(findPreviewUrl(''), isNull);
    });
  });
}
