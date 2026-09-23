import 'package:flutter_test/flutter_test.dart';

import 'package:cubiclm/services/app_log_service.dart'
    show isCrashExitReason, processExitReasonName, processImportanceName;

/// ApplicationExitInfo reason mapping for previous-run forensics.
/// Pure functions — no channel needed.
void main() {
  group('processExitReasonName', () {
    test('names the death kinds that matter', () {
      expect(processExitReasonName(2), 'SIGNALED');
      expect(processExitReasonName(3), 'LOW_MEMORY');
      expect(processExitReasonName(4), 'CRASH_NATIVE');
      expect(processExitReasonName(5), 'CRASH');
      expect(processExitReasonName(6), 'ANR');
      expect(processExitReasonName(1), 'EXIT_SELF');
      expect(processExitReasonName(99), 'REASON_99');
    });
  });

  group('processImportanceName', () {
    test('names foreground vs background states', () {
      expect(processImportanceName(100), 'FOREGROUND');
      expect(processImportanceName(125), 'FG_SERVICE');
      expect(processImportanceName(400), 'CACHED');
      expect(processImportanceName(1000), 'GONE');
      expect(processImportanceName(999), 'IMP_999');
    });
  });
  group('isCrashExitReason', () {
    test('flags abnormal deaths only', () {
      for (final r in [2, 3, 4, 5, 6, 7, 9, 13]) {
        expect(isCrashExitReason(r), isTrue, reason: 'reason $r');
      }
      for (final r in [0, 1, 8, 10, 11, 12, 14, 15]) {
        expect(isCrashExitReason(r), isFalse, reason: 'reason $r');
      }
    });
  });
}
