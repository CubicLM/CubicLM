import 'package:flutter/material.dart';

import 'device_info_widgets.dart';

/// CPU tab: static spec rows card (processor, ABIs, cores, GPU…).
/// Frequency lines derive from the static max/min tables; every param
/// is a plain snapshot — no Rx, no rebuilds on the sampling timer.
class CpuSpecsCard extends StatelessWidget {
  final String processor;
  final List<String> supportedAbis;
  final bool is64Bit;
  final String cpuHardware;
  final String governor;
  final int cores;
  final List<int> maxFreqs;
  final List<int> minFreqs;
  final String eglRenderer;
  final String eglVendor;
  final String eglVersion;
  /// Marketing cluster lines from the static SoC table when hardware
  /// matches; otherwise the measured table is used (no fake lines).
  final List<String>? archLinesOverride;
  const CpuSpecsCard({
    super.key,
    required this.processor,
    required this.supportedAbis,
    required this.is64Bit,
    required this.cpuHardware,
    required this.governor,
    required this.cores,
    required this.maxFreqs,
    required this.minFreqs,
    required this.eglRenderer,
    required this.eglVendor,
    required this.eglVersion,
    required this.archLinesOverride,
  });

  /// Group core indices by max freq → "N x min – max MHz" (desc).
  static List<String> _clusterMinMax(
      List<int> maxF, List<int> minF) {
    final groups = <int, List<int>>{};
    for (var i = 0; i < maxF.length; i++) {
      if (maxF[i] <= 0) continue;
      groups.putIfAbsent(maxF[i], () => []).add(i);
    }
    final keys = groups.keys.toList()
      ..sort((a, b) => b.compareTo(a));
    return [
      for (final k in keys)
        (() {
          var lo = 1 << 30;
          for (final i in groups[k]!) {
            final m = i < minF.length ? minF[i] : -1;
            if (m > 0 && m < lo) lo = m;
          }
          final n = groups[k]!.length;
          final hi = k >= 1000
              ? '${(k / 1000).toStringAsFixed(2)} GHz'
              : '$k MHz';
          final loS = lo == 1 << 30
              ? '?'
              : lo >= 1000
                  ? '${(lo / 1000).toStringAsFixed(2)} GHz'
                  : '$lo MHz';
          return '$n x $loS - $hi';
        })()
    ];
  }

  /// Group by max freq → "N x X.XX GHz" (desc).
  static List<String> _clusterMax(List<int> maxF) {
    final groups = <int, int>{};
    for (final f in maxF) {
      if (f <= 0) continue;
      groups[f] = (groups[f] ?? 0) + 1;
    }
    final keys = groups.keys.toList()
      ..sort((a, b) => b.compareTo(a));
    return [
      for (final k in keys)
        '${groups[k]} x ${(k / 1000).toStringAsFixed(2)} GHz'
    ];
  }

  @override
  Widget build(BuildContext context) {
    final abis = supportedAbis;
    final archLines =
        archLinesOverride ?? _clusterMax(maxFreqs);
    final freqLines = _clusterMinMax(maxFreqs, minFreqs);
    return devCard(context,
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            devRow(context, 'Processor', processor),
            devRow(context, 'CPU Architecture',
                archLines.isEmpty
                    ? '—'
                    : archLines.join('\n')),
            devRow(context, 'Supported ABIs',
                abis.isEmpty ? '—' : abis.join(', ')),
            devRow(context, 'CPU Hardware', cpuHardware),
            devRow(context, 'CPU Type',
                abis.isEmpty
                    ? '—'
                    : (is64Bit ? '64 Bit' : '32 Bit')),
            devRow(context, 'CPU Governor', governor),
            devRow(context, 'Cores',
                cores > 0 ? '$cores' : '—'),
            devRow(context, 'CPU Frequency',
                freqLines.isEmpty
                    ? '—'
                    : freqLines.join('\n')),
            devRow(
                context, 'GPU Renderer', eglRenderer),
            devRow(context, 'GPU Vendor', eglVendor),
            devRow(context, 'GPU Version', eglVersion,
                last: true),
          ],
        ));
  }
}
