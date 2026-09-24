import 'package:cubiclm/utils/greetings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('greeting bank', () {
    test('30+ greetings across 4 segments', () {
      var total = 0;
      for (final s in DaySegment.values) {
        final lines = greetingsFor(s);
        expect(lines.length, greaterThanOrEqualTo(8),
            reason: 'segment $s too small');
        total += lines.length;
      }
      expect(total, greaterThanOrEqualTo(30));
    });

    test('segment boundaries', () {
      expect(segmentFor(DateTime(2026, 1, 1, 4, 59)), DaySegment.night);
      expect(segmentFor(DateTime(2026, 1, 1, 5, 0)), DaySegment.morning);
      expect(segmentFor(DateTime(2026, 1, 1, 11, 59)), DaySegment.morning);
      expect(segmentFor(DateTime(2026, 1, 1, 12, 0)), DaySegment.afternoon);
      expect(segmentFor(DateTime(2026, 1, 1, 16, 59)), DaySegment.afternoon);
      expect(segmentFor(DateTime(2026, 1, 1, 17, 0)), DaySegment.evening);
      expect(segmentFor(DateTime(2026, 1, 1, 20, 59)), DaySegment.evening);
      expect(segmentFor(DateTime(2026, 1, 1, 21, 0)), DaySegment.night);
      expect(segmentFor(DateTime(2026, 1, 1, 0, 30)), DaySegment.night);
    });

    test('fillGreeting uses first name, falls back to friend', () {
      expect(fillGreeting('Hi {name}!', 'Abir Hasan'), 'Hi Abir!');
      expect(fillGreeting('Hi {name}!', '  '), 'Hi friend!');
      expect(fillGreeting('Hi {name}!', ''), 'Hi friend!');
    });

    test('greetingsNow returns filled lines for now', () {
      final lines = greetingsNow('Siam', DateTime(2026, 1, 1, 9));
      expect(lines.length, greaterThanOrEqualTo(8));
      expect(lines.every((l) => !l.contains('{name}')), isTrue);
      expect(lines.first, contains('Siam'));
    });

    test('templates fit the single-line typewriter', () {
      for (final s in DaySegment.values) {
        for (final t in greetingsFor(s)) {
          expect(t.length, lessThanOrEqualTo(44),
              reason: 'too long for one line: $t');
        }
      }
    });

    test('only the first line per segment names the user', () {
      for (final s in DaySegment.values) {
        final lines = greetingsFor(s);
        expect(lines.first, contains('{name}'),
            reason: 'segment $s should open with the name');
        for (var i = 1; i < lines.length; i++) {
          expect(lines[i], isNot(contains('{name}')),
              reason: 'repeat name in $s line $i: ${lines[i]}');
        }
      }
    });
  });
}
