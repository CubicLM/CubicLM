import 'package:flutter_test/flutter_test.dart';

import 'package:cubiclm/services/tts_service.dart';

/// Speech cleanup: everything a TTS engine would read as gibberish
/// must be stripped or summarized. Pure function.
void main() {
  group('cleanTextForSpeech', () {
    test('strips think blocks and special tokens', () {
      expect(
          cleanTextForSpeech(
              'Hi <think>secret reasoning</think> there <|im_end|>'),
          'Hi there');
    });

    test('summarizes big code blocks, reads one-liners', () {
      expect(
          cleanTextForSpeech(
              'See:\n```dart\nvoid main() {\n  runApp(X());\n}\n```\ndone'),
          contains('code snippet'));
      expect(cleanTextForSpeech('Use `print(x)` now'), contains('print(x)'));
      expect(cleanTextForSpeech('Use `this_is_a_very_long_identifier_name_here_ok` now'),
          contains('code'));
    });

    test('replaces bare URLs and keeps link text', () {
      expect(cleanTextForSpeech('See https://example.com/a?b=1 now'),
          isNot(contains('https')));
      expect(cleanTextForSpeech('See https://example.com now'),
          contains('link'));
      expect(cleanTextForSpeech('Read [the docs](https://x.io) now'),
          contains('the docs'));
    });

    test('replaces LaTeX math and strips emoji', () {
      expect(cleanTextForSpeech(r'Result $x^2 + 1$ ok'),
          isNot(contains(r'$')));
      expect(cleanTextForSpeech(r'Result $x^2 + 1$ ok'),
          contains('math expression'));
      expect(cleanTextForSpeech('Great 🎉 done'), 'Great done');
    });

    test('strips markdown markup', () {
      expect(cleanTextForSpeech('## Title'), 'Title');
      expect(cleanTextForSpeech('**bold** and *em*'), 'bold and em');
      expect(cleanTextForSpeech('> quote'), 'quote');
      expect(cleanTextForSpeech('- a\n- b'), 'a b');
    });
  });
}
