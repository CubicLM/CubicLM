import 'package:flutter_test/flutter_test.dart';

import 'package:cubiclm/utils/export_file.dart';

/// Export destination helpers: the subfolder name comes from user input,
/// so it must be sanitized before it ever reaches MediaStore or the
/// filesystem. Pure logic — no platform channels involved.
void main() {
  group('sanitizeExportSubfolder', () {
    test('keeps normal names untouched', () {
      expect(ExportFile.sanitizeExportSubfolder('CubicLM'), 'CubicLM');
      expect(ExportFile.sanitizeExportSubfolder('My Exports'), 'My Exports');
    });

    test('strips filesystem-illegal characters', () {
      expect(ExportFile.sanitizeExportSubfolder('a/b\\c:d*e?f"g<h>i|j'),
          'abcdefghij');
    });

    test('collapses whitespace and trims', () {
      expect(
          ExportFile.sanitizeExportSubfolder('  lots   of   space  '),
          'lots of space');
    });

    test('rejects blank and dot-only names', () {
      expect(ExportFile.sanitizeExportSubfolder(''), '');
      expect(ExportFile.sanitizeExportSubfolder('   '), '');
      expect(ExportFile.sanitizeExportSubfolder('.'), '');
      expect(ExportFile.sanitizeExportSubfolder('..'), '');
    });

    test('caps length at 32 chars', () {
      final long = List.filled(50, 'a').join();
      expect(ExportFile.sanitizeExportSubfolder(long).length, 32);
    });
  });

  group('resolveSubfolder', () {
    test('maps known categories under the app folder', () {
      final base = ExportFile.appSubfolder();
      expect(ExportFile.resolveSubfolder('logs'), '$base/System Logs');
      expect(ExportFile.resolveSubfolder('slides'), '$base/Slide Maker');
      expect(ExportFile.resolveSubfolder('datasheet'),
          '$base/CubicDataSheet');
      expect(ExportFile.resolveSubfolder('browser'),
          '$base/CubicWeb Browser');
      expect(ExportFile.resolveSubfolder('backup'), '$base/Backups');
    });

    test('category lookup is case-insensitive and trimmed', () {
      final base = ExportFile.appSubfolder();
      expect(ExportFile.resolveSubfolder('  LOGS '), '$base/System Logs');
    });

    test('unknown categories fall back to root (audit warning)', () {
      final base = ExportFile.appSubfolder();
      expect(ExportFile.resolveSubfolder('mystery-feature'), base);
      expect(ExportFile.resolveSubfolder(''), base);
      expect(ExportFile.resolveSubfolder(null), base);
    });

    test('registry covers every shipping exporter', () {
      for (final c in [
        'logs',
        'slides',
        'web',
        'datasheet',
        'browser',
        'chat',
        'cubicapp',
        'agent',
        'backup'
      ]) {
        expect(ExportFile.exportSubfolders.containsKey(c), isTrue,
            reason: 'missing folder for $c');
      }
    });
  });
}
