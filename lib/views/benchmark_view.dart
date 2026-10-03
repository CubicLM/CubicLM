import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';

import '../benchmark/benchmark_stats.dart';
import '../controllers/benchmark_controller.dart';
import '../core/colors.dart';
import '../services/inference_service.dart';
import '../theme/design_tokens.dart';
import 'device_info_widgets.dart';

/// Live local-AI benchmark page (CubicDevice Info → Category →
/// Benchmark). Warm-up (discarded) + 3 measured reps on the
/// production inference path, with a live gauge, streaming preview,
/// documented CubicLM AI Score, history and JSON export.
/// Nothing is simulated — estimates are labeled est, unknowns are —.
class BenchmarkView extends StatefulWidget {
  const BenchmarkView({super.key});

  @override
  State<BenchmarkView> createState() => _BenchmarkViewState();
}

class _BenchmarkViewState extends State<BenchmarkView> {
  late final BenchmarkController c;
  final _previewCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    c = Get.isRegistered<BenchmarkController>()
        ? Get.find<BenchmarkController>()
        : Get.put(BenchmarkController());
  }

  @override
  void dispose() {
    _previewCtrl.dispose();
    super.dispose();
  }

  void _scrollPreview() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        if (_previewCtrl.hasClients) {
          _previewCtrl.jumpTo(
              _previewCtrl.position.maxScrollExtent);
        }
      } catch (_) {}
    });
  }

  void _info(String title, String body) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: Text(title,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 15, fontWeight: FontWeight.w800)),
        content: SingleChildScrollView(
          child: Text(body,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 13, height: 1.55)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  Widget _infoBtn(String title, String body) {
    return InkWell(
      onTap: () => _info(title, body),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Icon(LucideIcons.info,
            size: 14,
            color: Theme.of(context)
                .hintColor
                .withValues(alpha: 0.8)),
      ),
    );
  }

  Future<void> _export(Map<String, dynamic> e) async {
    try {
      await Share.share(
          const JsonEncoder.withIndent('  ').convert(e),
          subject: 'CubicLM benchmark ${e['at'] ?? ''}');
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => Get.back(),
        ),
        title: Text('Benchmark',
            style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w800, fontSize: 20)),
      ),
      body: Obx(() {
        _scrollPreview();
        // ignore: unused_local_variable
        final tick = c.elapsedMs.value;
        final running = c.running.value;
        String model = '';
        int ctx = 0, gpuLayers = 0;
        var gpu = false;
        try {
          final inf = Get.find<InferenceService>();
          model = inf.loadedModelName.value;
          ctx = inf.contextTokensTotal.value;
          gpuLayers = inf.gpuLayersUsed.value;
          gpu = inf.isGpuAccelerated.value;
        } catch (_) {}
        final quant = _quantOf(model);
        return ListView(
          padding:
              const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            // ── Model card ──
            devCard(context,
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('MODEL',
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.0,
                                color: Theme.of(context)
                                    .hintColor)),
                        _infoBtn('Model card',
                            'Name is the loaded GGUF file. Quantization (e.g. Q4_K_M) is read from the filename — smaller quants run faster but answer worse. ctx is the runtime context window; GPU (N layers) vs CPU is the active backend. Benchmark always runs on this exact configuration.'),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                        model.isEmpty
                            ? 'No model loaded'
                            : model,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(
                        model.isEmpty
                            ? 'Load a local model from the Hub first.'
                            : '$quant · ctx $ctx · ${gpu ? 'GPU ($gpuLayers layers)' : 'CPU'}',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            color:
                                Theme.of(context).hintColor)),
                  ],
                )),
            const SizedBox(height: 12),
            // ── Gauge ──
            devCard(context,
                child: Column(
                  children: [
                    SizedBox(
                      height: 170,
                      child: CustomPaint(
                        painter: _GaugePainter(
                          value: running
                              ? (c.liveTps.value / 60.0)
                                  .clamp(0.0, 1.0)
                              : (c.doneScore.value >= 0
                                  ? c.doneScore.value /
                                      100.0
                                  : 0.0),
                          color: Dt.accent,
                          bg: Theme.of(context)
                              .dividerColor
                              .withValues(alpha: 0.35),
                        ),
                        child: Center(
                          child: Column(
                            mainAxisSize:
                                MainAxisSize.min,
                            children: [
                              const SizedBox(height: 34),
                              Text(
                                  running
                                      ? c.liveTps.value
                                          .toStringAsFixed(
                                              1)
                                      : (c.doneScore.value >=
                                              0
                                          ? '${c.doneScore.value}'
                                          : '—'),
                                  style: GoogleFonts
                                      .plusJakartaSans(
                                          fontSize: 34,
                                          fontWeight:
                                              FontWeight
                                                  .w800)),
                              Text(
                                  running
                                      ? 'tok/s live'
                                      : 'CubicLM AI Score',
                                  style: GoogleFonts
                                      .plusJakartaSans(
                                          fontSize: 11,
                                          color: Theme.of(
                                                  context)
                                              .hintColor)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment:
                          MainAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                              running
                                  ? '${c.phase.value} · ${(c.elapsedMs.value / 1000).toStringAsFixed(1)}s · ${c.liveTokens.value} tok'
                                  : c.phase.value,
                              textAlign: TextAlign.center,
                              style: GoogleFonts
                                  .plusJakartaSans(
                                      fontSize: 12,
                                      color: Theme.of(
                                              context)
                                          .hintColor)),
                        ),
                        _infoBtn('Gauge & phases',
                            'While running, the needle shows live generation speed (60 tok/s = full scale) and the text below shows phase, elapsed time and tokens so far.\n\nAfter the run it shows your CubicLM AI Score (0–100, CubicLM-defined, not an industry score).\n\nPhases: warm-up (result discarded) → 3 measured generations → statistics + score. Press Stop any time; partial reps are dropped, completed ones are kept.'),
                      ],
                    ),
                    if (running) ...[
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius:
                            BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: c.progress.value
                              .clamp(0.0, 1.0),
                          minHeight: 6,
                          backgroundColor:
                              Theme.of(context)
                                  .dividerColor
                                  .withValues(alpha: 0.35),
                          valueColor:
                              const AlwaysStoppedAnimation<
                                  Color>(Dt.accent),
                        ),
                      ),
                    ],
                  ],
                )),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: running
                  ? OutlinedButton.icon(
                      onPressed: c.stop,
                      icon: const Icon(
                          LucideIcons.square,
                          size: 16),
                      label: const Text('Stop'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor:
                            AppColors.error,
                        padding:
                            const EdgeInsets.symmetric(
                                vertical: 13),
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(
                                    14)),
                      ),
                    )
                  : FilledButton.icon(
                      onPressed: model.isEmpty
                          ? null
                          : () => c.run(),
                      icon: const Icon(
                          LucideIcons.gauge,
                          size: 18),
                      label: const Text(
                          'Run Benchmark'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Dt.accent,
                        foregroundColor: Colors.white,
                        padding:
                            const EdgeInsets.symmetric(
                                vertical: 13),
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(
                                    14)),
                      ),
                    ),
            ),
            // ── Live preview ──
            if (running || c.liveText.value.isNotEmpty) ...[
              const SizedBox(height: 12),
              devCard(context,
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text('LIVE INFERENCE',
                              style: GoogleFonts
                                  .plusJakartaSans(
                                      fontSize: 11,
                                      fontWeight:
                                          FontWeight.w800,
                                      letterSpacing:
                                          1.0,
                                      color: Theme.of(
                                              context)
                                          .hintColor)),
                          _infoBtn('Live preview',
                              'The actual tokens streaming out of your model right now — not an animation. Only the last ~1200 characters are kept on screen so the UI stays smooth; the full output is measured for the result.'),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        height: 140,
                        padding:
                            const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .dividerColor
                              .withValues(alpha: 0.18),
                          borderRadius:
                              BorderRadius.circular(
                                  10),
                        ),
                        child: SingleChildScrollView(
                          controller: _previewCtrl,
                          child: SelectableText(
                            c.liveText.value.isEmpty
                                ? '…'
                                : c.liveText.value,
                            style: GoogleFonts
                                .plusJakartaSans(
                                    fontSize: 12.5,
                                    height: 1.5),
                          ),
                        ),
                      ),
                    ],
                  )),
            ],
            // ── Latest result ──
            if (c.doneSummary.value != null) ...[
              const SizedBox(height: 12),
              _resultCard(context, c.doneSummary.value!),
            ],
            // ── Failures ──
            if (c.failures.isNotEmpty) ...[
              const SizedBox(height: 12),
              devCard(context,
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text('Errors',
                          style: GoogleFonts
                              .plusJakartaSans(
                                  fontSize: 13,
                                  fontWeight:
                                      FontWeight.w800,
                                  color:
                                      AppColors.error)),
                      for (final f in c.failures)
                        Padding(
                          padding:
                              const EdgeInsets.only(
                                  top: 4),
                          child: Text(f,
                              style: GoogleFonts
                                  .plusJakartaSans(
                                      fontSize: 12)),
                        ),
                    ],
                  )),
            ],
            const SizedBox(height: 12),
            // ── History ──
            devCard(context,
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('History',
                            style: GoogleFonts
                                .plusJakartaSans(
                                    fontSize: 13,
                                    fontWeight:
                                        FontWeight.w800)),
                        _infoBtn('History',
                            'Last 20 runs, newest first, stored on-device. Tap a row for the full report card, share icon exports that run as JSON, trash deletes it. Compare runs to see what a new model, backend or settings change did to your speed.'),
                      ],
                    ),
                    const SizedBox(height: 6),
                    if (c.history.isEmpty)
                      Text('No runs yet.',
                          style: GoogleFonts
                              .plusJakartaSans(
                                  fontSize: 12,
                                  color: Theme.of(
                                          context)
                                      .hintColor))
                    else
                      for (var i = 0;
                          i < c.history.length;
                          i++)
                        _historyRow(
                            context, c.history[i], i),
                  ],
                )),
            const SizedBox(height: 8),
            Text(
                'Score = gen/60·50 + TTFT decay·20 + PP/800·15 + stability·10 + thermal·5. PP uses estimated prompt tokens (chars÷4).',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    color: Theme.of(context).hintColor)),
          ],
        );
      }),
    );
  }

  String _quantOf(String filename) {
    final m = RegExp(r'Q\d[_\w]*', caseSensitive: false)
        .firstMatch(filename);
    return m?.group(0)?.toUpperCase() ?? '—';
  }

  Widget _resultCard(
      BuildContext context, Map<String, dynamic> e) {
    Widget kv(String k, String v, [String? info]) {
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          children: [
            SizedBox(
              width: 130,
              child: Text(k,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      color: Theme.of(context)
                          .hintColor)),
            ),
            Expanded(
              child: Text(v,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700)),
            ),
            if (info != null) _infoBtn(k, info),
          ],
        ),
      );
    }

    return devCard(context,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Result · Score ${e['score']}',
                      style:
                          GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              fontWeight:
                                  FontWeight.w800)),
                ),
                IconButton(
                  tooltip: 'Export JSON',
                  icon: const Icon(LucideIcons.share2,
                      size: 17),
                  onPressed: () => _export(e),
                ),
                IconButton(
                  tooltip: 'Delete',
                  icon: const Icon(
                      LucideIcons.trash2,
                      size: 17),
                  onPressed: () {
                    final i = c.history.indexWhere(
                        (h) => h['at'] == e['at']);
                    if (i >= 0) c.deleteRun(i);
                    if (c.doneSummary.value?['at'] ==
                        e['at']) {
                      c.doneSummary.value = null;
                      c.doneScore.value = -1;
                    }
                  },
                ),
              ],
            ),
            kv(
                'Generation',
                '${e['genAvg']} tok/s (med ${e['genMedian']}, min ${e['genMin']}, max ${e['genMax']}, sd ${e['genSd']})',
                'Average generation speed across successful reps (tokens ÷ generation seconds, prefill excluded). med/min/max/sd show consistency — tight numbers mean stable performance.'),
            kv(
                'Prompt (est)',
                '${e['ppTps']} tok/s',
                'Prompt-processing estimate: prompt chars ÷ 4 as token count, divided by time-to-first-token. Labeled est because the exact tokenizer count is not exposed — compare runs relatively, not against other apps.'),
            kv(
                'TTFT', '${e['ttftMs']} ms',
                'Time from request start to the first streamed token — what you feel as "responsiveness". Includes prompt processing.'),
            kv(
                'Reps',
                '${e['repsOk']}/${e['repsTotal']} ok',
                'Successful measured repetitions out of attempted. Failed or stopped reps are dropped and listed under Errors.'),
            kv(
                'RAM',
                'before ${_gb(e['ramBefore'])} · peak +${_gb(e['peakUsedGb'])} · after ${_gb(e['ramAfter'])}',
                'Device free RAM before the run, peak extra used during it, and after. Coarse 0.1 GB steps — small models may show +0.0.'),
            kv(
                'Battery',
                '${e['battStart']}% → ${e['battEnd']}%${(e['chargingStart'] == true) ? ' (charging)' : ''}',
                'Charge level at start and end. Percent steps are coarse — treat as context, not exact energy measurement.'),
            kv(
                'Thermal',
                '${thermalLabel((e['thermStart'] as num?)?.toInt() ?? -1)} → ${thermalLabel((e['thermEnd'] as num?)?.toInt() ?? -1)}',
                'PowerManager thermal status at start and end (NONE → SHUTDOWN). Heat throttles tok/s — a hot run scoring lower is thermal, not model, behavior.'),
            kv(
                'Model',
                '${e['model'] ?? '—'} · ${e['backend'] ?? ''} · ctx ${e['ctx'] ?? '—'}',
                'Exact configuration this result belongs to: model file, GPU/CPU backend with offloaded layers, and context window. Only compare runs with identical configuration.'),
          ],
        ));
  }

  String _gb(dynamic v) {
    if (v is! num || v < 0) return '—';
    return '${v.toStringAsFixed(1)} GB';
  }

  Widget _historyRow(
      BuildContext context, Map<String, dynamic> e, int i) {
    return InkWell(
      onTap: () =>
          Get.dialog(AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: Text('${e['model'] ?? 'Run'}',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                fontWeight: FontWeight.w800)),
        content: SingleChildScrollView(
            child: _resultCard(context, e)),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('Close'),
          ),
        ],
      )),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text('${e['model'] ?? '—'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          GoogleFonts.plusJakartaSans(
                              fontSize: 12.5,
                              fontWeight:
                                  FontWeight.w700)),
                  Text(
                      '${e['at']?.toString().substring(0, 16).replaceAll('T', ' ') ?? ''} · ${e['genAvg']} tok/s · score ${e['score']}',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 11.5,
                          color:
                              Theme.of(context).hintColor)),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Export JSON',
              icon: const Icon(LucideIcons.share2,
                  size: 16),
              onPressed: () => _export(e),
            ),
          ],
        ),
      ),
    );
  }
}

/// Analog semicircular gauge with needle (0..1 fraction).
class _GaugePainter extends CustomPainter {
  final double value;
  final Color color;
  final Color bg;
  const _GaugePainter(
      {required this.value,
      required this.color,
      required this.bg});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height - 12;
    const r = 78.0;
    final bgP = Paint()
      ..color = bg
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(Rect.fromCircle(center: Offset(cx, cy), radius: r),
        3.14159, 3.14159, false, bgP);
    final fgP = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(Rect.fromCircle(center: Offset(cx, cy), radius: r),
        3.14159, 3.14159 * value.clamp(0.0, 1.0), false, fgP);
    // Ticks at 0/25/50/75/100.
    final tickP = Paint()
      ..color = color.withValues(alpha: 0.5)
      ..strokeWidth = 2;
    for (var i = 0; i <= 4; i++) {
      final a = 3.14159 + 3.14159 * i / 4;
      canvas.drawLine(
          Offset(cx + 64 * cos(a), cy + 64 * sin(a)),
          Offset(cx + 70 * cos(a), cy + 70 * sin(a)),
          tickP);
    }
    // Needle.
    final na = 3.14159 + 3.14159 * value.clamp(0.0, 1.0);
    canvas.drawLine(
        Offset(cx, cy),
        Offset(cx + 58 * cos(na), cy + 58 * sin(na)),
        Paint()
          ..color = color
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round);
    canvas.drawCircle(
        Offset(cx, cy), 5, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _GaugePainter old) =>
      old.value != value ||
      old.color != color ||
      old.bg != bg;
}
