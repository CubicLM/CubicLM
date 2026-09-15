import 'package:flutter_test/flutter_test.dart';

import 'package:cubiclm/services/cloud/cloud_provider.dart';
import 'package:cubiclm/utils/text_sanitize.dart';

/// Regression tests for two device-logged crashes (Redmi K20 Pro, 1.15.1):
/// - TokenRouter 400 "Temperature must be between 0 and 1, got 2"
/// - "string is not well-formed UTF-16" in RenderEditable/TextSpan.
void main() {
  group('clampCloudTemperature', () {
    test('passes through in-range values', () {
      expect(clampCloudTemperature(0.0), 0.0);
      expect(clampCloudTemperature(0.7), 0.7);
      expect(clampCloudTemperature(1.0), 1.0);
    });

    test('clamps the 0–2 local slider range down to 1.0', () {
      expect(clampCloudTemperature(2.0), 1.0);
      expect(clampCloudTemperature(1.5), 1.0);
    });

    test('clamps negatives and passes null through', () {
      expect(clampCloudTemperature(-0.5), 0.0);
      expect(clampCloudTemperature(null), isNull);
    });
  });

  group('sanitizeUtf16', () {
    test('plain text untouched', () {
      expect(sanitizeUtf16('hello বাংলা world'), 'hello বাংলা world');
    });

    test('valid surrogate pairs (emoji) preserved', () {
      expect(sanitizeUtf16('hi 😀 bye'), 'hi 😀 bye');
    });

    test('lone high surrogate stripped', () {
      expect(sanitizeUtf16('ab\uD800cd'), 'abcd');
    });

    test('lone low surrogate stripped', () {
      expect(sanitizeUtf16('ab\uDC00cd'), 'abcd');
    });

    test('trailing high surrogate at chunk boundary stripped', () {
      expect(sanitizeUtf16('done\uD83D'), 'done');
    });

    test('empty string safe', () {
      expect(sanitizeUtf16(''), '');
    });
  });
}
