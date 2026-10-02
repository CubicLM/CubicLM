import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../controllers/device_info_controller.dart';
import '../services/device_info_service.dart';
import '../theme/design_tokens.dart';
import '../widgets/soc_brand_icon.dart';
import 'device_info_soc.dart';
import 'device_info_widgets.dart';

/// CPU tab: SoC header card + spec rows + live bars.
/// Marketing lines (name/clusters/process) come from the static SoC
/// table when hardware matches; otherwise measured data only.
class CpuTab extends StatelessWidget {
  final Future<AndroidDeviceInfo>? androidInfo;
  const CpuTab({super.key, required this.androidInfo});

  DeviceInfoController get c => Get.find<DeviceInfoController>();

  /// Group core indices by max freq → "N x min – max MHz" (desc).
  List<String> _clusterMinMax(List<int> maxF, List<int> minF) {
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
  List<String> _clusterMax(List<int> maxF) {
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
    return FutureBuilder<AndroidDeviceInfo>(
      future: androidInfo,
      builder: (context, snap) {
        final a = snap.data;
        return Obx(() {
          final dev = Get.find<DeviceInfoService>();
          final cpu = c.cpu.value;
          var maxF = const <int>[];
          var minF = const <int>[];
          try {
            maxF = (cpu?['maxFreqs'] as List?)
                    ?.map((e) => (e as num).toInt())
                    .toList() ??
                const [];
            minF = (cpu?['minFreqs'] as List?)
                    ?.map((e) => (e as num).toInt())
                    .toList() ??
                const [];
          } catch (_) {}
          final cores = maxF.isNotEmpty
              ? maxF.length
              : dev.cpuCores.value;
          final hw =
              '${dev.socHardware.value} ${a?.model ?? ''} ${a?.hardware ?? ''}';
          final spec = socSpecFor(hw);
          final img =
              SocBrandIcon.assetFor(dev.socFamily.value);
          final abis = a?.supportedAbis ?? const [];
          final is64 = (a?.supported64BitAbis ?? const [])
              .isNotEmpty;
          final freqs = c.extras.value?.cpuFreqsMHz ?? const [];
          var liveMax = 1;
          for (final f in freqs) {
            if (f > liveMax) liveMax = f;
          }
          final archLines = spec != null
              ? spec.clusters.map((e) => e.line).toList()
              : _clusterMax(maxF);
          final freqLines = _clusterMinMax(maxF, minF);
          String safe(dynamic v) {
            final s = v?.toString().trim() ?? '';
            return s.isEmpty ? '—' : s;
          }

          return ListView(
            padding:
                const EdgeInsets.fromLTRB(16, 4, 16, 32),
            children: [
              // SoC header (app card language, not the brown slab).
              devCard(context,
                  child: Row(
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          borderRadius:
                              BorderRadius.circular(14),
                          color: Dt.accent
                              .withValues(alpha: 0.10),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: img == null
                            ? const Icon(LucideIcons.cpu,
                                size: 30, color: Dt.accent)
                            : Image.asset(img,
                                fit: BoxFit.contain),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text(
                                spec?.name ??
                                    (dev.socHardware.value
                                            .isEmpty
                                        ? 'Processor'
                                        : dev.socHardware.value),
                                style: GoogleFonts
                                    .plusJakartaSans(
                                        fontSize: 15,
                                        fontWeight:
                                            FontWeight.w800)),
                            if (spec != null) ...[
                              const SizedBox(height: 4),
                              for (final cl
                                  in spec.clusters)
                                Text(cl.line,
                                    style: GoogleFonts
                                        .plusJakartaSans(
                                            fontSize: 12,
                                            color: Theme.of(
                                                    context)
                                                .hintColor)),
                              const SizedBox(height: 2),
                              Text(spec.process,
                                  style: GoogleFonts
                                      .plusJakartaSans(
                                          fontSize: 12,
                                          fontWeight:
                                              FontWeight.w600,
                                          color: Theme.of(
                                                  context)
                                              .hintColor)),
                            ],
                          ],
                        ),
                      ),
                      if (spec != null)
                        const Icon(
                            LucideIcons.badgeCheck,
                            size: 20,
                            color: Dt.accent),
                    ],
                  )),
              const SizedBox(height: 14),
              devCard(context,
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      devRow(context, 'Processor',
                          safe(dev.socHardware.value)),
                      devRow(context, 'CPU Architecture',
                          archLines.isEmpty
                              ? '—'
                              : archLines.join('\n')),
                      devRow(context, 'Supported ABIs',
                          abis.isEmpty
                              ? '—'
                              : abis.join(', ')),
                      devRow(context, 'CPU Hardware',
                          a?.hardware ?? '—'),
                      devRow(context, 'CPU Type',
                          abis.isEmpty
                              ? '—'
                              : (is64
                                  ? '64 Bit'
                                  : '32 Bit')),
                      devRow(context, 'CPU Governor',
                          safe(cpu?['governor'])),
                      devRow(context, 'Cores',
                          cores > 0 ? '$cores' : '—'),
                      devRow(context, 'CPU Frequency',
                          freqLines.isEmpty
                              ? '—'
                              : freqLines.join('\n')),
                      devRow(context, 'GPU Renderer',
                          safe(cpu?['eglRenderer'])),
                      devRow(context, 'GPU Vendor',
                          safe(cpu?['eglVendor'])),
                      devRow(
                          context,
                          'GPU Version',
                          safe(cpu?['eglVersion']),
                          last: true),
                    ],
                  )),
              // Live per-core bars (Dashboard grid shows the same).
              if (cores > 0) ...[
                const SizedBox(height: 14),
                devCard(context,
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Text('Live frequency',
                            style: GoogleFonts
                                .plusJakartaSans(
                                    fontSize: 13,
                                    fontWeight:
                                        FontWeight.w800)),
                        const SizedBox(height: 8),
                        for (var i = 0; i < cores; i++)
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(
                                    vertical: 6),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 64,
                                  child: Text('Core $i',
                                      style: GoogleFonts
                                          .plusJakartaSans(
                                              fontSize:
                                                  12.5)),
                                ),
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius:
                                        BorderRadius.circular(
                                            3),
                                    child:
                                        LinearProgressIndicator(
                                      value: i <
                                              freqs.length
                                          ? (freqs[i] /
                                                  liveMax)
                                              .clamp(
                                                  0.0, 1.0)
                                          : 0,
                                      minHeight: 6,
                                      backgroundColor:
                                          Theme.of(context)
                                              .dividerColor
                                              .withValues(
                                                  alpha:
                                                      0.4),
                                      valueColor:
                                          const AlwaysStoppedAnimation<
                                                  Color>(
                                              Dt.accent),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                SizedBox(
                                  width: 76,
                                  child: Text(
                                    i < freqs.length
                                        ? freqFmt(freqs[i])
                                        : '—',
                                    textAlign:
                                        TextAlign.end,
                                    style: GoogleFonts
                                        .plusJakartaSans(
                                            fontSize: 12,
                                            fontWeight:
                                                FontWeight
                                                    .w600),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    )),
              ],
            ],
          );
        });
      },
    );
  }
}
