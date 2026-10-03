import 'package:cubiclm/benchmark/benchmark_stats.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RepResult', () {
    test('gen throughput excludes prefill', () {
      const r = RepResult(
          promptTokensEst: 30,
          genTokens: 100,
          ttftMs: 2000,
          totalMs: 7000);
      expect(r.genSeconds, 5.0);
      expect(r.genTps, 20.0);
      expect(r.ppTpsEst, 15.0);
    });

    test('zero durations never divide', () {
      const r = RepResult(
          promptTokensEst: 0,
          genTokens: 0,
          ttftMs: 0,
          totalMs: 0);
      expect(r.genTps, 0.0);
      expect(r.ppTpsEst, 0.0);
    });
  });

  group('statistics', () {
    test('average/median/stddev', () {
      expect(average([10.0, 20.0, 30.0]), 20.0);
      expect(median([30.0, 10.0, 20.0]), 20.0);
      expect(median([10.0, 20.0]), 15.0);
      expect(average([]), 0.0);
      expect(median([]), 0.0);
      expect(stddev([]), 0.0);
      expect(stddev([5.0]), 0.0);
      expect(stddev([10.0, 20.0]), closeTo(7.07, 0.01));
    });
  });

  group('cubicAiScore', () {
    test('perfect device hits 100', () {
      expect(
          cubicAiScore(
              genAvg: 60,
              ttftAvgMs: 300,
              ppAvg: 800,
              okReps: 3,
              totalReps: 3,
              worstThermal: 0),
          100);
    });

    test('dead device scores 0-ish', () {
      final s = cubicAiScore(
          genAvg: 0,
          ttftAvgMs: 30000,
          ppAvg: 0,
          okReps: 0,
          totalReps: 3,
          worstThermal: 4);
      expect(s, lessThanOrEqualTo(2));
    });

    test('mid phone lands mid range', () {
      final s = cubicAiScore(
          genAvg: 8,
          ttftAvgMs: 2500,
          ppAvg: 120,
          okReps: 3,
          totalReps: 3,
          worstThermal: 2);
      expect(s, inInclusiveRange(20, 45));
    });

    test('thermal throttling costs points', () {
      final cool = cubicAiScore(
          genAvg: 20,
          ttftAvgMs: 800,
          ppAvg: 300,
          okReps: 3,
          totalReps: 3,
          worstThermal: 1);
      final hot = cubicAiScore(
          genAvg: 20,
          ttftAvgMs: 800,
          ppAvg: 300,
          okReps: 3,
          totalReps: 3,
          worstThermal: 4);
      expect(hot, cool - 3);
    });
  });

  group('thermalLabel', () {
    test('maps known states', () {
      expect(thermalLabel(0), 'NONE');
      expect(thermalLabel(2), 'MODERATE');
      expect(thermalLabel(6), 'SHUTDOWN');
      expect(thermalLabel(-1), '—');
      expect(thermalLabel(99), '—');
    });
  });
}
