import 'dart:math';

/// Pure benchmark math (no Flutter/Get imports, fully unit-tested).
/// Every metric originates from a real measurement; estimators are
/// explicitly labeled `est` and never mixed into measured fields.
class RepResult {
  /// Prompt tokens used for this rep (chars/4 estimate — labeled est).
  final double promptTokensEst;
  final int genTokens;
  final int ttftMs;
  final int totalMs;
  const RepResult({
    required this.promptTokensEst,
    required this.genTokens,
    required this.ttftMs,
    required this.totalMs,
  });

  /// Generation seconds excluding prefill.
  double get genSeconds =>
      max(1, totalMs - ttftMs) / 1000.0;

  double get genTps =>
      totalMs - ttftMs > 50 ? genTokens / genSeconds : 0.0;

  /// Prompt-processing throughput (ESTIMATED prompt tokens).
  double get ppTpsEst =>
      ttftMs > 50 ? promptTokensEst / (ttftMs / 1000.0) : 0.0;
}

double average(List<double> xs) {
  if (xs.isEmpty) return 0;
  return xs.reduce((a, b) => a + b) / xs.length;
}

double median(List<double> xs) {
  if (xs.isEmpty) return 0;
  final s = List<double>.from(xs)..sort();
  final m = s.length ~/ 2;
  return s.length.isOdd
      ? s[m]
      : (s[m - 1] + s[m]) / 2.0;
}

double stddev(List<double> xs) {
  if (xs.length < 2) return 0;
  final a = average(xs);
  var sum = 0.0;
  for (final x in xs) {
    sum += (x - a) * (x - a);
  }
  return sqrt(sum / (xs.length - 1));
}

/// CubicLM AI Score 0–100 (CubicLM-defined composite, NOT an
/// industry score). Documented formula:
/// - Generation 50: genAvg vs 60 tok/s reference (phone-class ceiling)
/// - TTFT 20: linear decay, full marks ≤400ms, zero at 5s+
/// - Prompt processing 15: ppAvg vs 800 tok/s reference (est. tokens)
/// - Stability 10: successful reps / total reps
/// - Thermal 5: 5 when worst status ≤ MODERATE, 4 when unknown
///   (no evidence of throttling, but no proof of cool either),
///   else 2
/// Each term is clamped to its weight; sum is rounded.
int cubicAiScore({
  required double genAvg,
  required double ttftAvgMs,
  required double ppAvg,
  required int okReps,
  required int totalReps,
  required int worstThermal,
}) {
  final gen = (genAvg / 60.0 * 50).clamp(0.0, 50.0);
  final ttft =
      (20.0 * (1.0 - (ttftAvgMs - 400) / 4600)).clamp(0.0, 20.0);
  final pp = (ppAvg / 800.0 * 15).clamp(0.0, 15.0);
  final stab = totalReps > 0 ? okReps / totalReps * 10.0 : 0.0;
  final thermScore =
      worstThermal < 0 ? 4.0 : (worstThermal <= 2 ? 5.0 : 2.0);
  return (gen + ttft + pp + stab + thermScore).round().clamp(0, 100);
}

/// Thermal status int (PowerManager 0..6) to label. -1 = unknown.
String thermalLabel(int s) {
  switch (s) {
    case 0:
      return 'NONE';
    case 1:
      return 'LIGHT';
    case 2:
      return 'MODERATE';
    case 3:
      return 'SEVERE';
    case 4:
      return 'CRITICAL';
    case 5:
      return 'EMERGENCY';
    case 6:
      return 'SHUTDOWN';
    default:
      return '—';
  }
}
