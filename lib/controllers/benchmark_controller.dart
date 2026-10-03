import 'dart:async';

import 'package:get/get.dart';

import '../benchmark/benchmark_stats.dart';
import '../services/device_extra_service.dart';
import '../services/device_info_service.dart';
import '../services/hive_service.dart';
import '../services/inference_service.dart';
import '../services/power_info_service.dart';

/// Live local-AI benchmark (CubicDevice Info → Category → Benchmark).
/// Runs on the PRODUCTION inference path (generate()) — warm-up is
/// discarded, then N measured reps. Nothing is simulated: every number
/// is measured, derived from measurements, or labeled est/—.
class BenchmarkController extends GetxController {
  static const historyKey = 'benchmark_history_v1';
  static const historyCap = 20;
  static const warmupPrompt =
      'Say exactly: warmup complete.';
  static const benchPrompt =
      'Explain in about 110 words why the sky looks blue. '
      'Plain sentences only, no lists.';

  final phase = 'Idle'.obs;
  final running = false.obs;
  final progress = 0.0.obs; // 0..1 across warmup + reps
  final liveText = ''.obs;
  final liveTps = 0.0.obs;
  final liveTokens = 0.obs;
  final elapsedMs = 0.obs;
  final reps = <RepResult>[].obs;
  final failures = <String>[].obs;
  final doneScore = (-1).obs;
  final doneSummary = Rxn<Map<String, dynamic>>();
  final history = <Map<String, dynamic>>[].obs;

  bool _stop = false;
  Timer? _clock;
  DateTime? _runStart;

  InferenceService get _inf {
    try {
      return Get.find<InferenceService>();
    } catch (_) {
      throw StateError('InferenceService not registered');
    }
  }

  HiveService get _hive {
    try {
      return Get.find<HiveService>();
    } catch (_) {
      throw StateError('HiveService not registered');
    }
  }

  @override
  void onInit() {
    super.onInit();
    loadHistory();
  }

  @override
  void onClose() {
    _clock?.cancel();
    super.onClose();
  }

  void loadHistory() {
    try {
      final raw = _hive.getSetting<List>(historyKey);
      if (raw == null) {
        history.clear();
        return;
      }
      history.value = [
        for (final e in raw)
          if (e is Map) Map<String, dynamic>.from(e),
      ];
    } catch (_) {}
  }

  Future<void> _saveHistory(Map<String, dynamic> entry) async {
    try {
      final list = [entry, ...history];
      while (list.length > historyCap) {
        list.removeLast();
      }
      history.value = list;
      await _hive.setSetting(historyKey, list);
    } catch (_) {}
  }

  Future<void> deleteRun(int i) async {
    try {
      final list = [...history];
      if (i >= 0 && i < list.length) list.removeAt(i);
      history.value = list;
      await _hive.setSetting(historyKey, list);
    } catch (_) {}
  }

  void stop() {
    _stop = true;
    try {
      unawaited(_inf.stopGeneration());
    } catch (_) {}
  }

  double _availGb() {
    try {
      return Get.find<DeviceInfoService>().availableRamGB.value;
    } catch (_) {
      return -1;
    }
  }

  Future<void> _refreshRam() async {
    try {
      await Get.find<DeviceInfoService>().refreshMemoryInfo();
    } catch (_) {}
  }

  /// PowerManager thermal status 0..6 (-1 unknown) for score +
  /// report. Same source as the Thermal tab.
  Future<int> _thermalStatus() async {
    try {
      final m = await DeviceExtraService.getThermalInfo();
      return (m?['status'] as num?)?.toInt() ?? -1;
    } catch (_) {
      return -1;
    }
  }

  /// One measured generation. Returns null on failure/stop (records
  /// the reason into [failures]).
  Future<RepResult?> _oneRep({
    required String prompt,
    required int repIndex,
    required int repTotal,
  }) async {
    final promptEst = prompt.length / 4.0;
    final t0 = DateTime.now();
    DateTime? firstAt;
    var tokens = 0;
    liveTokens.value = 0;
    final buf = StringBuffer();
    try {
      final out = await _inf.generate(
        prompt: prompt,
        source: 'benchmark',
        onToken: (t) {
          if (_stop) return;
          firstAt ??= DateTime.now();
          tokens++;
          buf.write(t);
          liveTokens.value = tokens;
          final el =
              DateTime.now().difference(t0).inMilliseconds;
          if (el > 500) {
            liveTps.value = tokens / (el / 1000.0);
          }
          // Stream the tail so the preview feels alive without
          // re-laying-out megabytes of text.
          final s = buf.toString();
          liveText.value =
              s.length > 1200 ? s.substring(s.length - 1200) : s;
        },
      );
      if (_stop) {
        failures.add('Rep ${repIndex + 1}: stopped by user');
        return null;
      }
      if (out.startsWith('ERROR')) {
        failures.add('Rep ${repIndex + 1}: $out');
        return null;
      }
      final totalMs =
          DateTime.now().difference(t0).inMilliseconds;
      return RepResult(
        promptTokensEst: promptEst,
        genTokens: tokens,
        ttftMs: firstAt?.difference(t0).inMilliseconds ??
            totalMs,
        totalMs: totalMs,
      );
    } catch (e) {
      failures.add('Rep ${repIndex + 1}: $e');
      return null;
    }
  }

  Future<void> run({int reps = 3}) async {
    if (running.value) return;
    if (_inf.isGenerating.value) {
      Get.snackbar('Benchmark Busy',
          'Wait for the current job to finish first.',
          snackPosition: SnackPosition.BOTTOM);
      return;
    }
    if (_inf.loadedModelName.value.isEmpty) {
      Get.snackbar('No model loaded',
          'Load a local model first, then benchmark.',
          snackPosition: SnackPosition.BOTTOM);
      return;
    }
    _stop = false;
    running.value = true;
    failures.clear();
    this.reps.clear();
    doneScore.value = -1;
    doneSummary.value = null;
    liveText.value = '';
    liveTps.value = 0;
    liveTokens.value = 0;
    _runStart = DateTime.now();
    _clock?.cancel();
    _clock = Timer.periodic(
        const Duration(milliseconds: 250), (_) {
      if (_runStart != null) {
        elapsedMs.value =
            DateTime.now().difference(_runStart!).inMilliseconds;
      }
    });
    try {
      final model = _inf.loadedModelName.value;
      final ctx = _inf.contextTokensTotal.value;
      final gpuLayers = _inf.gpuLayersUsed.value;
      final backend =
          _inf.isGpuAccelerated.value ? 'GPU' : 'CPU';
      await _refreshRam();
      final ramBefore = _availGb();
      final thermStart = await _thermalStatus();
      var battStart = -1;
      var chargingStart = false;
      try {
        final b = await PowerInfoService.getBattery(force: true);
        if (b != null) {
          battStart = b.level;
          chargingStart = b.charging;
        }
      } catch (_) {}
      var peakUsedGb = -1.0;
      void samplePeak() {
        final a = _availGb();
        if (ramBefore > 0 && a >= 0) {
          final used = ramBefore - a;
          if (used > peakUsedGb) peakUsedGb = used;
        }
      }

      // 1. Warm-up (discarded).
      phase.value = 'Warm-up (discarded)…';
      progress.value = 0.02;
      final warmFailures = failures.length;
      await _oneRep(
          prompt: warmupPrompt, repIndex: -1, repTotal: 1);
      // Relabel a warm-up failure (repIndex -1 reads as "Rep 0").
      if (failures.length > warmFailures) {
        failures[failures.length - 1] =
            failures.last.replaceFirst('Rep 0', 'Warm-up');
      }
      if (_stop) return;

      // 2. Measured reps.
      final ok = <RepResult>[];
      for (var i = 0; i < reps; i++) {
        if (_stop) return;
        phase.value = 'Generation ${i + 1}/$reps…';
        liveText.value = '';
        liveTps.value = 0;
        liveTokens.value = 0;
        final r = await _oneRep(
            prompt: benchPrompt,
            repIndex: i,
            repTotal: reps);
        if (r != null) {
          ok.add(r);
          this.reps.add(r);
        }
        await _refreshRam();
        samplePeak();
        progress.value = 0.05 + 0.9 * (i + 1) / reps;
        if (_stop) return;
      }
      if (ok.isEmpty) {
        phase.value = 'Failed — see errors below.';
        return;
      }
      await _refreshRam();
      final ramAfter = _availGb();
      samplePeak();
      var battEnd = -1;
      try {
        final b = await PowerInfoService.getBattery(force: true);
        if (b != null) battEnd = b.level;
      } catch (_) {}

      // 3. Statistics + score.
      final gens = [for (final r in ok) r.genTps];
      final tts = [
        for (final r in ok) r.ttftMs.toDouble()
      ];
      final pps = [for (final r in ok) r.ppTpsEst];
      final genAvg = average(gens);
      final ttftAvg = average(tts);
      final ppAvg = average(pps);
      final thermEnd = await _thermalStatus();
      final worstTherm = thermStart < 0
          ? thermEnd
          : (thermEnd < 0
              ? thermStart
              : (thermStart > thermEnd
                  ? thermStart
                  : thermEnd));
      final score = cubicAiScore(
        genAvg: genAvg,
        ttftAvgMs: ttftAvg,
        ppAvg: ppAvg,
        okReps: ok.length,
        totalReps: reps,
        worstThermal: worstTherm,
      );
      doneScore.value = score;
      final entry = {
        'at': DateTime.now().toIso8601String(),
        'model': model,
        'ctx': ctx,
        'gpuLayers': gpuLayers,
        'backend': backend,
        'genAvg': double.parse(genAvg.toStringAsFixed(1)),
        'genMedian':
            double.parse(median(gens).toStringAsFixed(1)),
        'genMin': double.parse(
            gens.reduce((a, b) => a < b ? a : b).toStringAsFixed(1)),
        'genMax': double.parse(
            gens.reduce((a, b) => a > b ? a : b).toStringAsFixed(1)),
        'genSd': double.parse(stddev(gens).toStringAsFixed(2)),
        'ttftMs': ttftAvg.round(),
        'ppTps':
            double.parse(ppAvg.toStringAsFixed(1)),
        'repsOk': ok.length,
        'repsTotal': reps,
        'ramBefore': ramBefore,
        'ramAfter': ramAfter,
        'peakUsedGb': peakUsedGb,
        'battStart': battStart,
        'battEnd': battEnd,
        'chargingStart': chargingStart,
        'thermStart': thermStart,
        'thermEnd': thermEnd,
        'score': score,
        'failures': [...failures],
      };
      doneSummary.value = entry;
      await _saveHistory(entry);
      unawaited(_refreshRam());
      phase.value = 'Complete — CubicLM AI Score $score/100.';
      progress.value = 1.0;
    } finally {
      _clock?.cancel();
      running.value = false;
      if (_stop) {
        phase.value = 'Stopped.';
        progress.value = 0.0;
      }
    }
  }
}
