import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cubiclm/services/terminal/terminal_service.dart';

void main() {
  group('withAutoConfirm', () {
    test('makes apt installs non-interactive', () {
      // Windows shells (cmd.exe) can't use the env prefix: contract is
      // passthrough there, wrapping everywhere else.
      if (Platform.isWindows) {
        expect(withAutoConfirm('apt install git'), 'apt install git');
        return;
      }
      final out = withAutoConfirm('apt install git');
      expect(out, contains('DEBIAN_FRONTEND=noninteractive'));
      expect(out, contains('-y'));
      expect(out, contains('force-confold'));
      expect(out, contains('apt install git'));
    });

    test('handles sudo + apt-get + existing flags idempotently', () {
      if (Platform.isWindows) return;
      final once = withAutoConfirm('sudo apt-get install -y curl');
      expect(once, contains('sudo apt-get'));
      expect(' $once '.split(' -y ').length - 1, 1);
      final twice = withAutoConfirm(once);
      expect(twice, once);
    });

    test('leaves non-actionable and non-apt commands alone', () {
      expect(withAutoConfirm('apt list --installed'), 'apt list --installed');
      expect(withAutoConfirm('apt --version'), 'apt --version');
      expect(withAutoConfirm('git status'), 'git status');
      expect(withAutoConfirm('echo hi'), 'echo hi');
      expect(withAutoConfirm(''), '');
    });
  });

  group('compactPromptPath', () {
    test('maps home to tilde, keeps the rest', () {
      expect(compactPromptPath('', home: '/h'), '');
      expect(compactPromptPath('/h', home: '/h'), '~');
      expect(compactPromptPath('/h/proj', home: '/h'), '~/proj');
      expect(compactPromptPath('/other/x', home: '/h'), '/other/x');
    });
  });

  group('shellQuote', () {
    test('single-quotes with embedded quote escape', () {
      expect(shellQuote('a b'), "'a b'");
      expect(shellQuote("it's"), "'it'\\''s'");
    });
  });

  group('CWD marker protocol', () {
    test('wrap then parse round-trips the directory', () {
      const marker = '__CLM_CWD_123_';
      final script = wrapWithCwdTracking('npm test', '/w/proj', marker);
      expect(script, contains("cd -- '/w/proj'"));
      expect(script, contains('npm test'));
      expect(script, contains(marker));
      final parsed = parseCwdMarker(
          'ok\n$marker/w/proj\nmore', marker);
      expect(parsed.cwd, '/w/proj');
      expect(parsed.clean, 'ok\nmore');
    });

    test('missing marker yields empty cwd, output kept', () {
      final parsed = parseCwdMarker('hello', '__CLM_CWD_x_');
      expect(parsed.cwd, '');
      expect(parsed.clean, 'hello');
    });
  });

  group('looksLikeConfirmPrompt', () {
    test('spots Y/n prompts case-insensitively', () {
      expect(looksLikeConfirmPrompt('Do you want to continue? [Y/n]'),
          isTrue);
      expect(looksLikeConfirmPrompt('done'), isFalse);
    });
  });
}
