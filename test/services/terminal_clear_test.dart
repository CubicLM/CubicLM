import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:cubiclm/services/terminal/terminal_service.dart';

void main() {
  group('TerminalService.clearAll', () {
    test('clears every session transcript, keeps history', () async {
      Get.testMode = true;
      final term = TerminalService();
      await term.init();
      term.lines.add(const TerminalLine('hello'));
      term.history.add('echo hi');
      term.switchSession('proj-1');
      term.lines.add(const TerminalLine('proj line'));
      term.switchSession(TerminalService.defaultSessionId);

      term.clearAll();

      expect(term.lines, isEmpty);
      expect(term.previewUrl.value, isNull);
      // Command history survives (reference-app parity).
      expect(term.history, contains('echo hi'));
      term.switchSession('proj-1');
      expect(term.lines, isEmpty);
      Get.reset();
    });
  });
}
