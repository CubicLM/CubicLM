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
  });
}
