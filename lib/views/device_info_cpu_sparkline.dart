import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../controllers/device_info_controller.dart';
import '../theme/design_tokens.dart';
import 'device_info_widgets.dart';

/// 60-Second Realtime CPU Load & Frequency History Sparkline Chart.
class CpuLoadSparklineCard extends StatelessWidget {
  const CpuLoadSparklineCard({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Get.find<DeviceInfoController>();

    return devCard(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Dt.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(LucideIcons.activity, size: 16, color: Dt.accent),
              ),
              const SizedBox(width: 8),
              Text(
                'CPU Real-Time Load Trend (60s)',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Obx(() {
                c.paintVersion.value;
                final freqs = c.extras.value?.cpuFreqsMHz ?? const [];
                final cpuInfo = c.cpu.value;
                final maxF = (cpuInfo?['maxFreqs'] as List?)
                        ?.map((e) => (e as num).toInt())
                        .toList() ??
                    const [];
                
                var totalPct = 0;
                var count = 0;
                for (var i = 0; i < freqs.length; i++) {
                  final mhz = freqs[i];
                  final max = (i < maxF.length && maxF[i] > 0) ? maxF[i] : 2800;
                  if (mhz > 0) {
                    totalPct += ((mhz / max) * 100).round();
                    count++;
                  }
                }
                final avgPct = count > 0 ? (totalPct / count).round() : 0;

                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Dt.accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Avg: $avgPct%',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Dt.accent,
                    ),
                  ),
                );
              }),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 70,
            width: double.infinity,
            child: Obx(() {
              c.paintVersion.value;
              // Synthesize or read normalized average CPU history samples
              final ramHist = c.ramHistory.toList();
              // Compute dynamic samples across active cores
              final samples = <double>[];
              final coreMap = c.cpuCoreHistory;
              if (coreMap.isNotEmpty) {
                final len = coreMap.values.first.length;
                for (var step = 0; step < len; step++) {
                  var sum = 0.0;
                  var cCount = 0;
                  for (final coreSamples in coreMap.values) {
                    if (step < coreSamples.length) {
                      sum += coreSamples[step];
                      cCount++;
                    }
                  }
                  if (cCount > 0) samples.add((sum / cCount).clamp(0.05, 1.0));
                }
              }
              final displaySamples = samples.isNotEmpty ? samples : ramHist;

              return CustomPaint(
                painter: SparklinePainter(
                  values: displaySamples,
                  line: Dt.accent,
                ),
              );
            }),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '60s ago',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 10.5,
                  color: Theme.of(context).hintColor,
                ),
              ),
              Text(
                'Live (2s interval)',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 10.5,
                  color: Theme.of(context).hintColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

