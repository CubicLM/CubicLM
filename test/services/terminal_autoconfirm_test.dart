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
}
